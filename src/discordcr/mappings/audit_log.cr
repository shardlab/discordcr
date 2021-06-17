module Discord
  struct AuditLog
    include JSON::Serializable

    property webhooks : Array(Webhook)
    property users : Array(User)
    property audit_log_entries : Array(AuditLogEntry)
    property integrations : Array(Integration)
  end

  struct AuditLogEntry
    include JSON::Serializable

    property target_id : String?
    property changes : Array(AuditLogChange)?
    property user_ud : Snowflake?
    property id : Snowflake
    @[JSON::Field(converter: Enum::ValueConverter(Discord::AuditLogEvent))]
    property action_type : AuditLogEvent
    property options : AuditEntryInfo?
    property reason : String?
  end

  enum AuditLogEvent
    GuildUpdate            =  1
    ChannelCreate          = 10
    ChannelUpdate          = 11
    ChannelDelete          = 12
    ChannelOverwriteCreate = 13
    ChannelOverwriteUpdate = 14
    ChannelOverwriteDelete = 15
    MemberKick             = 20
    MemberPrune            = 21
    MemberBanAdd           = 22
    MemberBanRemove        = 23
    MemberUpdate           = 24
    MemberRoleUpdate       = 25
    MemberMove             = 26
    MemberDisconnect       = 27
    BotAdd                 = 28
    RoleCreate             = 30
    RoleUpdate             = 31
    RoleDelete             = 32
    InviteCreate           = 40
    InviteUpdate           = 41
    InviteDelete           = 42
    WebhookCreate          = 50
    WebhookUpdate          = 51
    WebhookDelete          = 52
    EmojiCreate            = 60
    EmojiUpdate            = 61
    EmojiDelete            = 62
    MessageDelete          = 72
    MessageBulkDelete      = 73
    MessagePin             = 74
    MessageUnpin           = 75
    IntegrationCreate      = 80
    IntegrationUpdate      = 81
    IntegrationDelete      = 82
  end

  struct AuditEntryInfo
    include JSON::Serializable

    property delete_member_days : String?
    property members_removed : String?
    property channel_id : Snowflake?
    property message_id : Snowflake?
    property count : String?
    property id : Snowflake?
    property type : String?
    property role_name : String?
  end

  alias Mixed = String | Snowflake | Int32 | Bool | Array(Overwrite) | Array(PartialRole)

  struct AuditLogChange
    include JSON::Serializable

    property new_value : Mixed?
    property old_value : Mixed?
    property key : String?
  end
end
