module Discord
  struct Emoji
    include JSON::Serializable

    property id : Snowflake?
    property name : String?
    property roles : Array(Snowflake)?
    property user : User?
    property require_colons : Bool?
    property managed : Bool?
    property animated : Bool?
    property available : Bool?

    # Produces a CDN URL to this emoji's image in the given `size`. Will return
    # a PNG, or GIF if the emoji is animated.
    def image_url(size : Int32 = 128)
      if animated
        image_url(:gif, size)
      else
        image_url(:png, size)
      end
    end

    # Produces a CDN URL to this emoji's image in the given `format` and `size`
    # or `nil` if the emoji has no id.
    def image_url(format : CDN::ExtraImageFormat, size : Int32 = 128)
      if emoji_id = id
        CDN.custom_emoji(emoji_id, format, size)
      end
    end

    # Produces a string to mention this emoji in a message
    def mention
      if animated
        "<a:#{name}:#{id}>"
      else
        "<:#{name}:#{id}>"
      end
    end
  end
end
