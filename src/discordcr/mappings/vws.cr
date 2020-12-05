require "./converters"

module Discord
  # :nodoc:
  module VWS
    struct IdentifyPacket
      def initialize(server_id, user_id, session_id, token)
        @op = Discord::VoiceClient::OP_IDENTIFY
        @d = IdentifyPayload.new(server_id, user_id, session_id, token)
      end

      include JSON::Serializable

      property op : Int32
      property d : IdentifyPayload
    end

    struct IdentifyPayload
      def initialize(@server_id, @user_id, @session_id, @token)
      end

      include JSON::Serializable

      property server_id : UInt64
      property user_id : UInt64
      property session_id : String
      property token : String
    end

    struct SelectProtocolPacket
      def initialize(protocol, data)
        @op = Discord::VoiceClient::OP_SELECT_PROTOCOL
        @d = SelectProtocolPayload.new(protocol, data)
      end

      include JSON::Serializable

      property op : Int32
      property d : SelectProtocolPayload
    end

    struct SelectProtocolPayload
      def initialize(@protocol, @data)
      end

      include JSON::Serializable

      property protocol : String
      property data : ProtocolData
    end

    struct ProtocolData
      def initialize(@address, @port, @mode)
      end

      include JSON::Serializable

      property address : String
      property port : UInt16
      property mode : String
    end

    struct ReadyPayload
      include JSON::Serializable

      property ssrc : Int32
      property port : Int32
      property modes : Array(String)
      property ip : String
    end

    struct SessionDescriptionPayload
      include JSON::Serializable

      property secret_key : Array(UInt8)
      property mode : String
    end

    struct SpeakingPacket
      def initialize(speaking, delay)
        @op = Discord::VoiceClient::OP_SPEAKING
        @d = SpeakingPayload.new(speaking, delay)
      end

      include JSON::Serializable

      property op : Int32
      property d : SpeakingPayload
    end

    struct SpeakingPayload
      def initialize(@speaking, @delay)
      end

      include JSON::Serializable

      property speaking : Bool
      property delay : Int32
    end

    struct HelloPayload
      include JSON::Serializable

      property heartbeat_interval : Float32
    end
  end
end
