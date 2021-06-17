module Discord
  @[Flags]
  enum Permissions : UInt64
    CreateInstantInvite = 1 << 0
    KickMembers         = 1 << 1
    BanMembers          = 1 << 2
    Administrator       = 1 << 3
    ManageChannels      = 1 << 4
    ManageGuild         = 1 << 5
    AddReactions        = 1 << 6
    ViewAuditLog        = 1 << 7
    PrioritySpeaker     = 1 << 8
    Stream              = 1 << 9
    ReadMessages        = 1 << 10 # VIEW_CHANNEL
    SendMessages        = 1 << 11
    SendTTSMessages     = 1 << 12
    ManageMessages      = 1 << 13
    EmbedLinks          = 1 << 14
    AttachFiles         = 1 << 15
    ReadMessageHistory  = 1 << 16
    MentionEveryone     = 1 << 17
    UseExternalEmojis   = 1 << 18
    Connect             = 1 << 20
    Speak               = 1 << 21
    MuteMembers         = 1 << 22
    DeafenMembers       = 1 << 23
    MoveMembers         = 1 << 24
    UseVAD              = 1 << 25
    ChangeNickname      = 1 << 26
    ManageNicknames     = 1 << 27
    ManageRoles         = 1 << 28
    ManageWebhooks      = 1 << 29
    ManageEmojis        = 1 << 30
    UseSlashCommands    = 1 << 31
    RequestToSpeak      = 1 << 32

    def self.new(pull : JSON::PullParser)
      Permissions.new(pull.read_string.to_u64)
    end

    def to_json(json : JSON::Builder)
      json.string(value)
    end
  end

  struct Role
    include JSON::Serializable

    property id : Snowflake
    property name : String
    @[JSON::Field(key: "color")]
    property colour : UInt32
    property hoist : Bool
    property position : Int32
    property permissions : Permissions
    property managed : Bool
    property mentionable : Bool
    property tags : RoleTags?

    {% unless flag?(:correct_english) %}
      def color
        colour
      end
    {% end %}

    # Produces a string to mention this role in a message
    def mention
      "<@&#{id}>"
    end
  end

  struct PartialRole
    include JSON::Serializable

    property id : Snowflake
    property name : String
  end

  struct RoleTags
    include JSON::Serializable

    property bot_id : Snowflake?
    property integration_id : Snowflake?
    # property premium_subscriber : Nil # As of writing, the type in Discord dos is `null`
  end
end
