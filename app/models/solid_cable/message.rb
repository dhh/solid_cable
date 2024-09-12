# frozen_string_literal: true

module SolidCable
  class Message < SolidCable::Record
    scope :trimmable, lambda {
      where(created_at: ..::SolidCable.message_retention.ago)
    }
    scope :broadcastable, lambda { |channels, last_id|
      where(channel: channels).where(id: (last_id + 1)..).order(:id)
    }
  end
end
