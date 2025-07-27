# frozen_string_literal: true

class FlaggedFingerprint < ActiveRecord::Base
  # A fingerprint value must exist and be unique for each flagged record.
  # This enforces data integrity at the application level.
  validates :value, presence: true, uniqueness: true

  # Scopes for easily querying records based on their flag type.
  # This allows for cleaner code in the controller, e.g., `FlaggedFingerprint.hidden`
  scope :hidden, -> { where(hidden: true) }
  scope :silenced, -> { where(silenced: true) }
end

# == Schema Information
#
# Table name: flagged_fingerprints
#
#  id         :bigint           not null, primary key
#  value      :string           not null
#  hidden     :boolean          default(FALSE), not null
#  silenced   :boolean          default(FALSE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_flagged_fingerprints_on_hidden    (hidden)
#  index_flagged_fingerprints_on_silenced  (silenced)
#  index_flagged_fingerprints_on_value     (value)
#
