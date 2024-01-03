# frozen_string_literal: true

module ActionCable
  module SubscriptionAdapter
    class SolidCable < Base
      prepend ChannelPrefix

      def initialize(*)
        super
        @listener = nil
      end

      def broadcast(channel, payload)
        ::SolidCable::Message.create(channel:, payload:)
      end

      def subscribe(channel, callback, success_callback = nil)
        listener.add_subscriber(channel, callback, success_callback)
      end

      def unsubscribe(channel, callback)
        listener.remove_subscriber(channel, callback)
      end

      delegate :shutdown, to: :listener

      private

      def listener
        @listener || @server.mutex.synchronize do
          @listener ||= Listener.new(@server.event_loop)
        end
      end

      class Listener < SubscriberMap
        def initialize(event_loop)
          super()

          @event_loop = event_loop

          @thread = Thread.new do
            Thread.current.abort_on_exception = true
            listen
          end
        end

        def listen
          while running?
            with_polling_volume { broadcast_messages }

            sleep SolidCable.polling_interval
          end
        end

        def shutdown
          self.running = false
          ::SolidCable::Message.prune
          Thread.pass while thread.alive?
        end

        def add_channel(channel, on_success)
          channels.add(channel)
          event_loop.post(&on_success) if on_success
        end

        def remove_channel(channel)
          channels.delete(channel)
        end

        def invoke_callback(*)
          event_loop.post { super }
        end

        private

        attr_reader :event_loop, :thread
        attr_writer :running, :last_id

        def running?
          if defined?(@running)
            @running
          else
            self.running = true
          end
        end

        def last_id
          @last_id ||= ::SolidCable::Message.maximum(:id) || 0
        end

        def channels
          @channels ||= Set.new
        end

        def broadcast_messages
          ::SolidCable::Message.broadcastable(channels, last_id).
            each do |message|
              broadcast(message.channel, message.payload)
              self.last_id = message.id
            end
        end

        def with_polling_volume
          if ::SolidCable.silence_polling?
            ActiveRecord::Base.logger.silence { yield }
          else
            yield
          end
        end
      end
    end
  end
end
