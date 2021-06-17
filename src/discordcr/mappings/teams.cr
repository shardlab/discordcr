module Discord
  struct Team
    include JSON::Serializable

    property icon : String?
    property id : Snowflake
    property members : Array(TeamMember)
    property name : String
    property owner_user_id : Snowflake

    # Produces a CDN URL for this team's icon in the given `format` and `size`
    def icon_url(format : CDN::ImageFormat = CDN::ImageFormat::WebP, size : Int32 = 128)
      if icon = @icon
        CDN.team_icon(id, icon, format, size)
      end
    end
  end

  struct TeamMember
    include JSON::Serializable

    @[JSON::Field(converter: Enum::ValueConverter(Discord::MembershipState))]
    property membership_state : MembershipState
    property permissions : Array(String)
    property team_id : Snowflake
    # Partial User containing only the id, username, discriminator, and avatar
    property user : User
  end

  enum MembershipState
    Invited  = 1
    Accepted = 2
  end
end
