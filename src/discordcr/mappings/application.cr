module Discord
  # An OAuth2 application, as registered with Discord, that can hold
  # information about a `Client`'s associated bot user account and owner,
  # among other OAuth2 properties.
  struct Application
    include JSON::Serializable

    property id : Snowflake
    property name : String
    property icon : String?
    property description : String
    property rpc_origins : Array(String)?
    property bot_public : Bool
    property bot_require_code_grant : Bool
    property terms_of_service_url : String?
    property privacy_policy_url : String?
    # Partial User containing only the id, username, discriminator, flags, and avatar
    property owner : User
    property summary : String
    property verify_key : String
    property team : Team?
    property guild_id : Snowflake?
    property primary_sku_id : Snowflake?
    property slug : String?
    property cover_image : String?
    @[JSON::Field(converter: Enum::ValueConverter(Discord::ApplicationFlags))]
    property flags : ApplicationFlags?

    # Produces a CDN URL for this application's icon in the given `format` and `size`
    def icon_url(format : CDN::ImageFormat = CDN::ImageFormat::WebP, size : Int32 = 128)
      if icon = @icon
        CDN.application_icon(id, icon, format, size)
      end
    end

    # Produces a CDN URL for this application's cover icon in the given `format` and `size`
    def cover_url(format : CDN::ImageFormat = CDN::ImageFormat::WebP, size : Int32 = 128)
      if cover = @cover_image
        CDN.application_icon(id, cover, format, size)
      end
    end
  end

  @[Flags]
  enum ApplicationFlags
    GatewayPresence               = 1 << 12
    GatewayPresenceLimited        = 1 << 13
    GatewayGuildMembers           = 1 << 14
    GatewayGuildMembersLimited    = 1 << 15
    VerificationPendingGuildLimit = 1 << 16
    Embedded                      = 1 << 17
    UnknownFlag                   = 1 << 18 # WTH IS THIS
  end
end
