module Discord
  # :nodoc:
  module VWS
    struct IdentifyPacket
      include JSON::Serializable

      property op : Int32
      property d : IdentifyPayload

      def initialize(server_id, user_id, session_id, token)
        @op = Discord::VoiceClient::OP_IDENTIFY
        @d = IdentifyPayload.new(server_id, user_id, session_id, token)
      end
    end

    struct IdentifyPayload
      include JSON::Serializable

      property server_id : UInt64
      property user_id : UInt64
      property session_id : String
      property token : String

      def initialize(@server_id, @user_id, @session_id, @token)
      end
    end

    struct SelectProtocolPacket
      include JSON::Serializable

      property op : Int32
      property d : SelectProtocolPayload

      def initialize(protocol, data)
        @op = Discord::VoiceClient::OP_SELECT_PROTOCOL
        @d = SelectProtocolPayload.new(protocol, data)
      end
    end

    struct SelectProtocolPayload
      include JSON::Serializable

      property protocol : String
      property data : ProtocolData

      def initialize(@protocol, @data)
      end
    end

    struct ProtocolData
      include JSON::Serializable

      property address : String
      property port : UInt16
      property mode : String

      def initialize(@address, @port, @mode)
      end
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
      include JSON::Serializable

      property op : Int32
      property d : SpeakingPayload

      def initialize(speaking, delay)
        @op = Discord::VoiceClient::OP_SPEAKING
        @d = SpeakingPayload.new(speaking, delay)
      end
    end

    struct SpeakingPayload
      include JSON::Serializable

      property speaking : Bool
      property delay : Int32

      def initialize(@speaking, @delay)
      end
    end

    struct HelloPayload
      include JSON::Serializable

      property heartbeat_interval : Float32
    end
  end
end
