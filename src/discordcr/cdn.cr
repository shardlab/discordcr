# This module contains methods for building URLs to resources on Discord's CDN
# for things like guild icons and avatars.
#
# NOTE: All `size` arguments for CDN methods must be a power of 2 between 16
# and 2048. If an invalid size is given, `ArgumentError` will be raised.
#
# [API Documentation for image formatting](https://discord.com/developers/docs/reference#image-formatting)
module Discord::CDN
  extend self

  # Base CDN URL
  BASE_URL = "https://cdn.discordapp.com"

  # Available image formats for most endpoints
  enum ImageFormat
    PNG
    JPEG
    WebP

    def to_s
      super.downcase
    end
  end

  # Available image formats for Custom Emoji, Guild Icon, and User Avatar endpoints
  enum ExtraImageFormat
    PNG
    JPEG
    WebP
    GIF

    def to_s
      super.downcase
    end
  end

  private def check_size(value : Int32)
    in_range = (16..2048).includes?(value)
    power_of_two = (value > 0) && ((value & (value - 1)) == 0)
    unless in_range && power_of_two
      raise ArgumentError.new("Size #{value} is not between 16 and 2048 and a power of 2")
    end
  end

  # Produces a CDN URL for a custom emoji in the given `format` and `size`
  def custom_emoji(id : UInt64 | Snowflake, format : ExtraImageFormat = ExtraImageFormat::PNG, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/emojis/#{id}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for a guild icon in the given `format` and `size`
  def guild_icon(id : UInt64 | Snowflake, icon : String, format : ExtraImageFormat = ExtraImageFormat::WebP, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/icons/#{id}/#{icon}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for a guild splash in the given `format` and `size`
  def guild_splash(id : UInt64 | Snowflake, splash : String, format : ImageFormat = ImageFormat::WebP, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/splashes/#{id}/#{splash}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for a guild discovery splash in the given `format` and `size`
  def guild_discovery_splash(id : UInt64 | Snowflake, discovery_splash : String, format : ImageFormat = ImageFormat::WebP, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/discovery-splashes/#{id}/#{discovery_splash}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for a guild banner in the given `format` and `size`
  def guild_banner(id : UInt64 | Snowflake, banner : String, format : ImageFormat = ImageFormat::WebP, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/banners/#{id}/#{banner}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for a default user avatar, calculated from the given
  # discriminator value.
  def default_user_avatar(user_discriminator : String)
    index = user_discriminator.to_i % 5
    "#{BASE_URL}/embed/avatars/#{index}.png"
  end

  # Produces a CDN URL for a user avatar in the given `size`. Given the `avatar`
  # string, this will return a WebP or GIF based on the animated avatar hint.
  def user_avatar(id : UInt64 | Snowflake, avatar : String, size : Int32 = 128)
    if avatar.starts_with?("a_")
      user_avatar(id, avatar, ExtraImageFormat::GIF, size)
    else
      user_avatar(id, avatar, ExtraImageFormat::WebP, size)
    end
  end

  # Produces a CDN URL for a user avatar in the given `format` and `size`
  def user_avatar(id : UInt64 | Snowflake, avatar : String, format : ExtraImageFormat, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/avatars/#{id}/#{avatar}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for an application icon in the given `format` and `size`
  def application_icon(id : UInt64 | Snowflake, icon : String, format : ImageFormat = ImageFormat::WebP, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/app-icons/#{id}/#{icon}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for an application asset in the given `format` and `size`
  def application_asset(application_id : UInt64 | Snowflake, asset_id : UInt64 | Snowflake, format : ImageFormat = ImageFormat::PNG, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/app-assets/#{application_id}/#{asset_id}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for an achievement icon in the given `format` and `size`
  def achievement_icon(application_id : UInt64 | Snowflake, achievement_id : UInt64, icon : String, format : ImageFormat = ImageFormat::PNG, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/app-assets/#{application_id}/achievements/#{achievement_id}/icons/#{icon}.#{format}?size=#{size}"
  end

  # Produces a CDN URL for an team icon in the given `format` and `size`
  def team_icon(team_id : UInt64 | Snowflake, icon : String, format : ImageFormat = ImageFormat::PNG, size : Int32 = 128)
    check_size(size)
    "#{BASE_URL}/team-icons/#{application_id}/#{asset_id}.#{format}?size=#{size}"
  end
end
