require "./converters"
require "./user"
require "./channel"
require "./guild"

module Discord
  module Gateway
    struct ReadyPayload
      include JSON::Serializable

      property v : UInt8
      property user : User
      property private_channels : Array(PrivateChannel)
      property guilds : Array(UnavailableGuild)
      property session_id : String
    end

    struct ResumedPayload
      include JSON::Serializable

      property _trace : Array(String)
    end

    struct IdentifyPacket
      include JSON::Serializable

      property op : Int32
      property d : IdentifyPayload

      def initialize(token, properties, large_threshold, compress, shard, intents)
        @op = Discord::Client::OP_IDENTIFY
        @d = IdentifyPayload.new(token, properties, large_threshold, compress, shard, intents)
      end
    end

    struct IdentifyPayload
      include JSON::Serializable

      property token : String
      property properties : IdentifyProperties
      property compress : Bool
      property large_threshold : Int32
      property shard : Tuple(Int32, Int32)?

      @[JSON::Field(converter: Enum::ValueConverter)]
      property intents : Intents?

      def initialize(@token, @properties, @compress, @large_threshold, @shard, @intents)
      end
    end

    struct IdentifyProperties
      include JSON::Serializable

      @[JSON::Field(key: "$os")]
      property os : String
      @[JSON::Field(key: "$browser")]
      property browser : String
      @[JSON::Field(key: "$device")]
      property device : String
      @[JSON::Field(key: "$referrer")]
      property referrer : String
      @[JSON::Field(key: "$referring_domain")]
      property referring_domain : String

      def initialize(@os, @browser, @device, @referrer, @referring_domain)
      end
    end

    @[Flags]
    enum Intents
      Guilds                 = 1 << 0
      GuildMembers           = 1 << 1
      GuildBans              = 1 << 2
      GuildEmojis            = 1 << 3
      GuildIntegrations      = 1 << 4
      GuildWebhooks          = 1 << 5
      GuildInvites           = 1 << 6
      GuildVoiceStates       = 1 << 7
      GuildPresences         = 1 << 8
      GuildMessages          = 1 << 9
      GuildMessageReactions  = 1 << 10
      GuildMessageTyping     = 1 << 11
      DirectMessages         = 1 << 12
      DirectMessageReactions = 1 << 13
      DirectMessageTyping    = 1 << 14
    end

    struct ResumePacket
      include JSON::Serializable

      property op : Int32
      property d : ResumePayload

      def initialize(token, session_id, seq)
        @op = Discord::Client::OP_RESUME
        @d = ResumePayload.new(token, session_id, seq)
      end
    end

    # :nodoc:
    struct ResumePayload
      include JSON::Serializable

      property token : String
      property session_id : String
      property seq : Int64

      def initialize(@token, @session_id, @seq)
      end
    end

    struct StatusUpdatePacket
      include JSON::Serializable

      property op : Int32
      property d : StatusUpdatePayload

      def initialize(status, game, afk, since)
        @op = Discord::Client::OP_STATUS_UPDATE
        @d = StatusUpdatePayload.new(status, game, afk, since)
      end
    end

    # :nodoc:
    struct StatusUpdatePayload
      include JSON::Serializable

      @[JSON::Field(emit_null: true)]
      property status : String?
      @[JSON::Field(emit_null: true)]
      property game : GamePlaying?
      property afk : Bool
      @[JSON::Field(emit_null: true)]
      property since : Int64?

      def initialize(@status, @game, @afk, @since)
      end
    end

    struct VoiceStateUpdatePacket
      include JSON::Serializable

      property op : Int32
      property d : VoiceStateUpdatePayload

      def initialize(guild_id, channel_id, self_mute, self_deaf)
        @op = Discord::Client::OP_VOICE_STATE_UPDATE
        @d = VoiceStateUpdatePayload.new(guild_id, channel_id, self_mute, self_deaf)
      end
    end

    # :nodoc:
    struct VoiceStateUpdatePayload
      include JSON::Serializable

      property guild_id : UInt64
      @[JSON::Field(emit_null: true)]
      property channel_id : UInt64?
      property self_mute : Bool
      property self_deaf : Bool

      def initialize(@guild_id, @channel_id, @self_mute, @self_deaf)
      end
    end

    struct RequestGuildMembersPacket
      include JSON::Serializable

      property op : Int32
      property d : RequestGuildMembersPayload

      def initialize(guild_id, query, limit)
        @op = Discord::Client::OP_REQUEST_GUILD_MEMBERS
        @d = RequestGuildMembersPayload.new(guild_id, query, limit)
      end
    end

    # :nodoc:
    struct RequestGuildMembersPayload
      include JSON::Serializable

      property guild_id : UInt64
      property query : String
      property limit : Int32

      def initialize(@guild_id, @query, @limit)
      end
    end

    struct HelloPayload
      include JSON::Serializable

      property heartbeat_interval : UInt32
      property _trace : Array(String)
    end

    # This one is special from simply Guild since it also has fields for members
    # and presences.
    struct GuildCreatePayload
      include JSON::Serializable

      property id : Snowflake
      property name : String
      property icon : String?
      property splash : String?
      property owner_id : Snowflake
      property region : String
      property afk_channel_id : Snowflake?
      property afk_timeout : Int32?
      property verification_level : UInt8
      property premium_tier : UInt8
      property premium_subscription_count : UInt8?
      property roles : Array(Role)
      @[JSON::Field(key: "emojis")]
      property emoji : Array(Emoji)
      property features : Array(String)
      property large : Bool
      property voice_states : Array(VoiceState)
      property unavailable : Bool?
      property member_count : Int32
      property members : Array(GuildMember)
      property channels : Array(Channel)
      property presences : Array(Presence)
      property widget_channel_id : Snowflake?
      property default_message_notifications : UInt8
      property explicit_content_filter : UInt8
      property system_channel_id : Snowflake?
      property stage_instances : Array(StageInstance)
      property threads : Array(Channel)

      {% unless flag?(:correct_english) %}
        def emojis
          emoji
        end
      {% end %}
    end

    struct GuildDeletePayload
      include JSON::Serializable

      property id : Snowflake
      property unavailable : Bool?
    end

    struct GuildBanPayload
      include JSON::Serializable

      property user : User
      property guild_id : Snowflake
    end

    struct GuildEmojiUpdatePayload
      include JSON::Serializable

      property guild_id : Snowflake
      @[JSON::Field(key: "emojis")]
      property emoji : Array(Emoji)

      {% unless flag?(:correct_english) %}
        def emojis
          emoji
        end
      {% end %}
    end

    struct GuildIntegrationsUpdatePayload
      include JSON::Serializable

      property guild_id : Snowflake
    end

    struct GuildMemberAddPayload
      include JSON::Serializable

      property user : User
      property nick : String?
      property roles : Array(Snowflake)
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property joined_at : Time?
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property premium_since : Time?
      property deaf : Bool
      property mute : Bool
      property guild_id : Snowflake
    end

    struct GuildMemberUpdatePayload
      include JSON::Serializable

      property user : User
      property roles : Array(Snowflake)
      property nick : String?
      property guild_id : Snowflake
    end

    struct GuildMemberRemovePayload
      include JSON::Serializable

      property user : User
      property guild_id : Snowflake
    end

    struct GuildMembersChunkPayload
      include JSON::Serializable

      property guild_id : Snowflake
      property members : Array(GuildMember)
    end

    struct GuildRolePayload
      include JSON::Serializable

      property guild_id : Snowflake
      property role : Role
    end

    struct GuildRoleDeletePayload
      include JSON::Serializable

      property guild_id : Snowflake
      property role_id : Snowflake
    end

    struct InviteCreatePayload
      include JSON::Serializable

      property channel_id : Snowflake
      property code : String
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property created_at : Time?
      property guild_id : Snowflake?
      property inviter : User?
      property max_age : Int32
      property max_uses : Int32
      property temporary : Bool
      property uses : Int32
    end

    struct InviteDeletePayload
      include JSON::Serializable

      property channel_id : Snowflake
      property guild_id : Snowflake?
      property code : String
    end

    struct MessageReactionPayload
      include JSON::Serializable

      property user_id : Snowflake
      property channel_id : Snowflake
      property message_id : Snowflake
      property guild_id : Snowflake?
      property emoji : ReactionEmoji
    end

    struct MessageReactionRemoveAllPayload
      include JSON::Serializable

      property channel_id : Snowflake
      property message_id : Snowflake
      property guild_id : Snowflake?
    end

    struct MessageReactionRemoveEmojiPayload
      include JSON::Serializable

      property channel_id : Snowflake
      property guild_id : Snowflake
      property message_id : Snowflake
      property emoji : ReactionEmoji
    end

    struct MessageUpdatePayload
      include JSON::Serializable

      property type : UInt8?
      property content : String?
      property id : Snowflake
      property channel_id : Snowflake
      property guild_id : Snowflake?
      property author : User?
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property timestamp : Time?
      property tts : Bool?
      property mention_everyone : Bool?
      property mentions : Array(User)?
      property mention_roles : Array(Snowflake)?
      property attachments : Array(Attachment)?
      property embeds : Array(Embed)?
      property pinned : Bool?
    end

    struct MessageDeletePayload
      include JSON::Serializable

      property id : Snowflake
      property channel_id : Snowflake
      property guild_id : Snowflake?
    end

    struct MessageDeleteBulkPayload
      include JSON::Serializable

      property ids : Array(Snowflake)
      property channel_id : Snowflake
      property guild_id : Snowflake?
    end

    struct PresenceUpdatePayload
      include JSON::Serializable

      property user : PartialUser
      property game : GamePlaying?
      property guild_id : Snowflake
      property status : String
      property activities : Array(GamePlaying)
    end

    struct TypingStartPayload
      include JSON::Serializable

      property channel_id : Snowflake
      property user_id : Snowflake
      property guild_id : Snowflake?
      property member : GuildMember?
      @[JSON::Field(converter: Time::EpochConverter)]
      property timestamp : Time
    end

    struct VoiceServerUpdatePayload
      include JSON::Serializable

      property token : String
      property guild_id : Snowflake
      property endpoint : String
    end

    struct WebhooksUpdatePayload
      include JSON::Serializable

      property guild_id : Snowflake
      property channel_id : Snowflake
    end

    struct ChannelPinsUpdatePayload
      include JSON::Serializable

      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property last_pin_timestamp : Time?
      property channel_id : Snowflake
    end

    struct ThreadMembersUpdatePayload
      include JSON::Serializable

      property id : Snowflake
      property guild_id : Snowflake
      property member_count : UInt32
      property added_members : Array(ThreadMember)?
      property removed_member_ids : Array(Snowflake)?
    end

    struct ThreadListSyncPayload
      include JSON::Serializable

      property guild_id : Snowflake
      property channel_ids : Array(Snowflake)?
      property threads : Array(Channel)
      property members : Array(ThreadMember)
    end
  end
end
