# frozen_string_literal: true

module DiscourseFingerprint
  class FingerprintAdminController < Admin::AdminController
    requires_plugin DiscourseFingerprint::PLUGIN_NAME

    before_action :ensure_fingerprint_value, only: [:flag]
    before_action :ensure_flag_type, only: [:flag]
    before_action :ensure_ignore_users, only: [:ignore]

    # Main dashboard endpoint.
    def index
      # 1. Load all flagged fingerprint values into a hash for efficient lookups.
      flagged_map = FlaggedFingerprint.all.index_by(&:value)
      flagged_values = flagged_map.keys

      # 2. Fetch the top 50 most recently active, unflagged fingerprint matches.
      matches =
        Fingerprint
          .matches
          .where.not(value: flagged_values)
          .order("MAX(updated_at) DESC")
          .limit(50)

      # 3. Fetch counts for fingerprints that are already flagged.
      flagged_fingerprints_data =
        Fingerprint
          .select(:name, :value, "MAX(data) AS data", "COUNT(*) AS count")
          .where(value: flagged_values)
          .group(:name, :value)
          .index_by(&:value)

      # 4. Collect all relevant user IDs and load user objects efficiently.
      user_ids = matches.flat_map(&:user_ids).uniq
      users = User.where(id: user_ids)
      # Preload avatars to prevent N+1 queries in the serializer.
      Discourse.preloader.preload(users, :user_avatar)

      render json: {
        fingerprints: serialize_data(
          matches,
          FingerprintSerializer,
          scope: { flagged: flagged_map }
        ),
        flagged: serialize_data(
          flagged_map.values,
          FlaggedFingerprintSerializer,
          scope: { fingerprints: flagged_fingerprints_data }
        ),
        users: serialize_data(users, BasicUserSerializer)
      }
    end

    # Report for a single user.
    def user_report
      user = User.find_by_username!(params[:username])
      ignored_ids = DiscourseFingerprint.get_ignores(user)

      user_fingerprints =
        Fingerprint
          .where(user: user)
          .where.not(value: FlaggedFingerprint.select(:value).where(hidden: true))
          .order(updated_at: :desc)

      # Find users who share fingerprints with the target user.
      user_ids_by_fingerprint =
        Fingerprint
          .matches
          .where(value: user_fingerprints.pluck(:value))
          .each_with_object({}) do |match, memo|
            memo[match.value] = match.user_ids - [user.id]
          end

      # Load all associated users in a single query.
      all_user_ids = user_ids_by_fingerprint.values.flatten.uniq + ignored_ids
      users = User.where(id: all_user_ids)
      Discourse.preloader.preload(users, :user_avatar)

      render json: {
        user: BasicUserSerializer.new(user, root: false),
        ignored_ids: ignored_ids,
        fingerprints: serialize_data(
          user_fingerprints,
          FingerprintSerializer,
          scope: { user_ids: user_ids_by_fingerprint }
        ),
        users: serialize_data(users, BasicUserSerializer)
      }
    end

    # Flags a fingerprint as hidden or silenced.
    def flag
      should_add = params[:remove].blank?
      flagged = FlaggedFingerprint.find_or_initialize_by(value: @fingerprint_value)

      case @flag_type
      when "hide"
        flagged.hidden = should_add
      when "silence"
        flagged.silenced = should_add
      end

      if flagged.hidden || flagged.silenced
        flagged.save!
      else
        flagged.destroy if flagged.persisted?
      end

      render json: success_json
    end

    # Ignores or un-ignores a pair of users.
    def ignore
      should_add = params[:remove].blank?

      DiscourseFingerprint.ignore(@user1, @user2, add: should_add)
      DiscourseFingerprint.ignore(@user2, @user1, add: should_add)

      render json: success_json
    end

    private

    def ensure_fingerprint_value
      @fingerprint_value = params[:value]
      raise Discourse::InvalidParameters.new(:value) if @fingerprint_value.blank?
    end

    def ensure_flag_type
      @flag_type = params[:type]
      raise Discourse::InvalidParameters.new(:type) unless %w[hide silence].include?(@flag_type)
    end

    def ensure_ignore_users
      usernames = [params[:username], params[:other_username]].compact
      users = User.where(username: usernames)

      raise Discourse::InvalidParameters.new if users.size != 2
      @user1, @user2 = users[0], users[1]
    end
  end
end
