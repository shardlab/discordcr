module Discord
  abstract struct InviteAbstract
    include JSON::Serializable

    property code : String
    property guild : InviteGuild?
    property channel : Channel
    property inviter : User?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::InviteTargetType))]
    property target_type : InviteTargetType?
    property target_user : User?
    property target_application : Application? # NOTE: Untested, might rise
    property approximate_presence_count : UInt32?
    property approximate_member_count : UInt32?
    @[JSON::Field(converter: Discord::MaybeTimestampConverter)]
    property expires_at : Time?
  end

  struct Invite < InviteAbstract
  end

  enum InviteTargetType
    Stream              = 1
    EmbeddedApplication = 2
  end

  struct InviteMetadata < InviteAbstract
    property uses : UInt32
    property max_uses : UInt32
    property max_age : UInt32
    property temporary : Bool
    @[JSON::Field(converter: Discord::TimestampConverter)]
    property created_at : Time
  end

  # Specia partial guild object for the Invite object
  struct InviteGuild
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property splash : String?
    property banner : String?
    property description : String?
    property icon : String?
    property features : Array(String)
    @[JSON::Field(converter: Enum::ValueConverter(Discord::VerificationLevel))]
    property verification_level : VerificationLevel
    property vanity_url_code : String?
  end
end
