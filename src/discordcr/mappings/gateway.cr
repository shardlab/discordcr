require "./user"
require "./channel"
require "./guild"
require "./slash_commands"
require "./stage_instance"

module Discord
  module Gateway
    #
    # Gateway Commands
    #

    struct IdentifyPacket
      include JSON::Serializable

      property op : Int32
      property d : IdentifyPayload

      def initialize(token, properties, large_threshold, compress, shard, presence, intents)
        @op = Discord::Client::OP_IDENTIFY
        @d = IdentifyPayload.new(token, properties, large_threshold, compress, shard, presence, intents)
      end
    end

    struct IdentifyPayload
      include JSON::Serializable

      property token : String
      property properties : IdentifyProperties
      property compress : Bool
      property large_threshold : Int32
      property shard : Tuple(Int32, Int32)?
      property presence : StatusUpdatePayload?

      @[JSON::Field(converter: Enum::ValueConverter)]
      property intents : Intents

      def initialize(@token, @properties, @compress, @large_threshold, @shard, @presence, @intents)
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

      def initialize(@os, @browser, @device)
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

    struct StatusUpdatePacket
      include JSON::Serializable

      property op : Int32
      property d : StatusUpdatePayload

      def initialize(status, activities, afk, since)
        @op = Discord::Client::OP_STATUS_UPDATE
        @d = StatusUpdatePayload.new(status, activities, afk, since)
      end
    end

    # :nodoc:
    struct StatusUpdatePayload
      include JSON::Serializable

      @[JSON::Field(emit_null: true)]
      property since : UInt64?
      @[JSON::Field(emit_null: true)]
      property activities : Array(Activity)?
      property status : String
      property afk : Bool

      def initialize(@status = "online", @activities = nil, @afk = false, @since = nil)
      end
    end

    #
    # Gateway Events
    #

    struct HelloPayload
      include JSON::Serializable

      property heartbeat_interval : UInt32
      property _trace : Array(String)
    end

    struct ReadyPayload
      include JSON::Serializable

      property v : UInt8
      property user : User
      property guilds : Array(UnavailableGuild)
      property session_id : String
      property shard : Array(Int32)?
      property application : PartialApplication
    end

    struct PartialApplication
      include JSON::Serializable

      property id : Snowflake
      @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationFlags))]
      property flags : ApplicationFlags
    end

    struct ResumedPayload
      include JSON::Serializable

      property _trace : Array(String)
    end

    struct ReconnectPayload
      include JSON::Serializable

      property _trace : Array(String)
    end

    struct ChannelPinsUpdatePayload
      include JSON::Serializable

      property guild_id : Snowflake?
      property channel_id : Snowflake
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property last_pin_timestamp : Time?
    end

    # This one is special from simply Guild since it also has fields for members
    # and presences.
    struct GuildCreatePayload < GuildAbstract
      @[JSON::Field(converter: Discord::TimestampConverter)]
      property joined_at : Time
      property large : Bool
      property unavailable : Bool
      property member_count : UInt32
      property voice_states : Array(VoiceState)
      property members : Array(GuildMember)
      property channels : Array(Channel)
      property presences : Array(PresenceUpdatePayload)
      property stage_instances : Array(StageInstance)
    end

    struct GuildDeletePayload
      include JSON::Serializable

      property id : Snowflake
      property unavailable : Bool?
    end

    struct GuildBanPayload
      include JSON::Serializable

      property guild_id : Snowflake
      property user : User
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

    struct GuildMemberAddPayload < GuildMemberAbstract
      property guild_id : Snowflake
    end

    struct GuildMemberRemovePayload
      include JSON::Serializable

      property guild_id : Snowflake
      property user : User
    end

    struct GuildMemberUpdatePayload
      include JSON::Serializable

      property guild_id : Snowflake
      property roles : Array(Snowflake)
      property user : User
      property nick : String?
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property joined_at : Time
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property premium_since : Time?
      property deaf : Bool?
      property mute : Bool?
      property pending : Bool?
    end

    struct GuildMembersChunkPayload
      include JSON::Serializable

      property guild_id : Snowflake
      property members : Array(GuildMember)
      property chunk_index : UInt32
      property chunk_count : UInt32
      property not_found : Bool?
      property presences : Array(PresenceUpdatePayload)?
      property nonce : String?
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

    struct IntegrationPayload < IntegrationAbstract
      property guild_id : Snowflake
    end

    struct IntegrationDeletePayload
      include JSON::Serializable

      property id : Snowflake
      property guild_id : Snowflake
      property application_id : Snowflake?
    end

    struct InviteCreatePayload
      include JSON::Serializable

      property channel_id : Snowflake
      property code : String
      @[JSON::Field(converter: Discord::TimestampConverter)]
      property created_at : Time
      property guild_id : Snowflake?
      property inviter : User?
      property max_age : Int32
      property max_uses : Int32
      @[JSON::Field(converter: Enum::ValueConverter(Discord::InviteTargetType))]
      property target_type : InviteTargetType?
      property target_user : User?
      property target_application : Application? # NOTE: Untested, might rise
      property temporary : Bool
      property uses : Int32
    end

    struct InviteDeletePayload
      include JSON::Serializable

      property channel_id : Snowflake
      property guild_id : Snowflake?
      property code : String
    end

    struct MessageUpdatePayload
      include JSON::Serializable

      property id : Snowflake
      property channel_id : Snowflake
      property guild_id : Snowflake?
      property author : User?
      property member : GuildMember?
      property content : String?
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property timestamp : Time?
      @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
      property edited_timestamp : Time?
      property tts : Bool?
      property mention_everyone : Bool?
      property mentions : Array(User)?
      property mention_roles : Array(Snowflake)?
      property mention_channels : Array(ChannelMention)?
      property attachments : Array(Attachment)?
      property embeds : Array(Embed)?
      property reactions : Array(Reaction)?
      property nonce : String | Int64?
      property pinned : Bool?
      property webhook_id : Snowflake?
      @[JSON::Field(converter: Enum::ValueConverter(Discord::MessageType))]
      property type : MessageType?
      property activity : MessageActivity?
      property application : Application?
      property application_id : Snowflake?
      property message_reference : MessageReference?
      @[JSON::Field(converter: Enum::ValueConverter(Discord::MessageFlags))]
      property flags : MessageFlags?
      property stickers : Array(Sticker)?
      property referenced_message : Message?
      property interaction : MessageInteraction?
      property components : Array(Component)?
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

    struct MessageReactionPayload
      include JSON::Serializable

      property user_id : Snowflake
      property channel_id : Snowflake
      property message_id : Snowflake
      property guild_id : Snowflake?
      property member : GuildMember?
      property emoji : Emoji
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
      property guild_id : Snowflake?
      property message_id : Snowflake
      property emoji : Emoji
    end

    struct PresenceUpdatePayload
      include JSON::Serializable

      property user : PartialUser
      # This is nilable to get rid of a pointless Presence struct
      property guild_id : Snowflake?
      property status : String
      property activities : Array(Activity)
      property client_status : ClientStatus
    end

    struct ClientStatus
      include JSON::Serializable

      property desktop : String?
      property mobile : String?
      property web : String?
    end

    struct Activity
      include JSON::Serializable

      enum Type : UInt8
        Playing   = 0
        Streaming = 1
        Listening = 2
        Watching  = 3
        Custom    = 4
        Competing = 5
      end

      property name : String
      @[JSON::Field(converter: Enum::ValueConverter(Discord::Gateway::Activity::Type))]
      property type : Type
      property url : String?
      @[JSON::Field(converter: Time::EpochMillisConverter)]
      property created_at : Time
      property timestamps : Timestamps?
      property application_id : Snowflake?
      property details : String?
      property state : String?
      property emoji : Emoji?
      property party : ActivityParty?
      property assets : ActivityAssets?
      property secrets : ActivitySecrets?
      property instance : Bool?
      @[JSON::Field(converter: Enum::ValueConverter(Discord::Gateway::ActivityFlags))]
      property flags : ActivityFlags?
      property buttons : Array(ActivityButton)?

      def initialize(@name = nil, @type = Type::Playing, @url = nil, @state = nil, @emoji = nil, @created_at = Time.utc)
      end
    end

    struct Timestamps
      include JSON::Serializable

      @[JSON::Field(converter: Time::EpochMillisConverter)]
      property start : Time?
      @[JSON::Field(key: "end", converter: Time::EpochMillisConverter)]
      property end_time : Time?
    end

    struct ActivityParty
      include JSON::Serializable

      property id : Snowflake?
      property size : Array(Int32)?
    end

    struct ActivityAssets
      include JSON::Serializable

      property large_image : String?
      property large_text : String?
      property small_image : String?
      property small_text : String?
    end

    struct ActivitySecrets
      include JSON::Serializable

      property join : String?
      property spectate : String?
      property match : String?
    end

    @[Flags]
    enum ActivityFlags
      Instance    = 1 << 0
      Join        = 1 << 1
      Spectate    = 1 << 2
      JoinRequest = 1 << 3
      Sync        = 1 << 4
      Play        = 1 << 5
    end

    struct ActivityButton
      include JSON::Serializable

      property label : String
      property url : String
    end

    struct TypingStartPayload
      include JSON::Serializable

      property channel_id : Snowflake
      property guild_id : Snowflake?
      property user_id : Snowflake
      @[JSON::Field(converter: Time::EpochConverter)]
      property timestamp : Time
      property member : GuildMember?
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

    struct ApplicationCommandPayload < ApplicationCommandAbstract
      property guild_id : Snowflake?
    end
  end
end
