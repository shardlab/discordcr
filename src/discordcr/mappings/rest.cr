module Discord
  module REST
    # A response to the Get Gateway REST API call.
    struct GatewayResponse
      include JSON::Serializable

      property url : String
    end

    # A response to the Get Gateway Bot REST API call.
    struct GatewayBotResponse
      include JSON::Serializable

      property url : String
      property shards : Int32
      property session_start_limit : SessionStartLimit
    end

    # Session start limit details included in the Get Gateway Bot REST API call.
    struct SessionStartLimit
      include JSON::Serializable

      property total : Int32
      property remaining : Int32
      @[JSON::Field(converter: Discord::TimeSpanMillisecondsConverter)]
      property reset_after : Time::Span
      property max_concurrency : Int32
    end

    # A response to the Get Guild Prune Count REST API call.
    struct PruneCountResponse
      include JSON::Serializable

      property pruned : UInt32
    end

    # A response to the Get Guild Vanity URL REST API call.
    struct GuildVanityURLResponse
      include JSON::Serializable

      property code : String
    end

    # A request payload to rearrange channels in a `Guild` by a REST API call.
    struct ModifyChannelPositionPayload
      @_internal = {} of String => (Int32 | Bool | UInt64 | Snowflake | Nil)

      # Valid args: position: Int32, lock_permissions: Bool, parent_id: UInt64 | Snowflake | Nil
      # Note: `parent_id: nil` will send null, and not setting `parent_id` will result in `parent_id` not being present
      #
      # To see valid fields, see `VALID_MODIFY_CHANNEL_POSITION_PAYLOAD_ARGS` constant (beneath this method in code)
      def initialize(id : UInt64 | Snowflake, **args : **T) forall T
        @_internal["id"] = id.is_a?(Snowflake) ? id : Snowflake.new(id)
        TypeCheck.args_check(args, VALID_MODIFY_CHANNEL_POSITION_PAYLOAD_ARGS).each { |k, v| @_internal[k] = v }
      end

      VALID_MODIFY_CHANNEL_POSITION_PAYLOAD_ARGS = {
        :position         => TypeCheck(Int32),
        :lock_permissions => TypeCheck(Bool),
        :parent_id        => TypeCheck(UInt64 | Snowflake | Nil),
      }

      def to_json(builder : JSON::Builder)
        @_internal.to_json(builder)
      end
    end

    # A request payload to rearrange roles in a `Guild` by a REST API call.
    struct ModifyRolePositionPayload
      include JSON::Serializable

      property id : Snowflake
      property position : Int32

      def initialize(id : UInt64 | Snowflake, @position : Int32)
        @id = id.is_a?(Snowflake) ? id : Snowflake.new(id)
      end
    end

    struct TypeCheck(T)
      def self.check(value)
        value.is_a?(T)
      end

      def self.type
        T
      end

      def self.args_check(args, valid : Hash(Symbol, TypeCheck.class))
        args.map do |key, value|
          raise "field '#{key}' does not exist" unless valid[key]?
          raise "field '#{key}' is of invalid type (must be #{valid[key].type})" unless valid[key].check(value)
          {key.to_s, value}
        end.to_h
      end
    end
  end
end
