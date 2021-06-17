require "./spec_helper"

describe Discord::REST do
  describe "#encode_tuple" do
    it "doesn't emit null values" do
      client = Discord::Client.new("foo", 0_u64)
      client.encode_tuple(foo: ["bar", 1, 2], baz: nil).should eq(%({"foo":["bar",1,2]}))
    end

    it "emits values correctly" do
      client = Discord::Client.new("foo", 0_u64)
      client.encode_tuple(string: "foobar", int: 12345678, array: ["barfoo", "testfoo"], hash: {"bar" => 3.14, "foo" => "rab"}, enum_value: Discord::NSFWLevel::Explicit).should eq(%({"string":"foobar","int":12345678,"array":["barfoo","testfoo"],"hash":{"bar":3.14,"foo":"rab"},"enum_value":1}))
    end
  end
end

#
# Discord REST API Tests
#
# These tests require a valid Discord Bot Token, Guild ID, Channel ID, and User ID.
# Bot is required to have all permissions in given Guild and Channel.
# During tests chnages will be applied to given Guild and Channel so it is
# advised to only run these tests on a "test" Guild and Channel.
#
# You might also want to provide an Application ID for the Application Command tests.
#
# NOTE: These tests can take a while to complete (around 1 minute and 30 seconds) due to rate limiting

{% unless env("TOKEN") && env("GUILD") && env("CHANNEL") && env("USER") %}
  {{ skip_file }}
{% end %}

TEST_GUILD   = {{ env("GUILD") }}.to_u64
TEST_CHANNEL = {{ env("CHANNEL") }}.to_u64
TEST_USER    = {{ env("USER") }}.to_u64

CLIENT = Discord::Client.new "Bot " + {{ env("TOKEN") }}

describe Discord::REST do
  describe "#get_gateway" do
    it "retrives Discord gateway URL" do
      CLIENT.get_gateway.should be_a(Discord::REST::GatewayResponse)
    end
  end

  describe "#get_gateway_bot" do
    it "retrives Discord gateway bot URL and sharding information" do
      CLIENT.get_gateway_bot.should be_a(Discord::REST::GatewayBotResponse)
    end
  end

  describe "#get_oauth2_application" do
    it "retrives OAuth2 Application for current bot" do
      CLIENT.get_oauth2_application.should be_a(Discord::Application)
    end
  end

  describe "#get_audit_log" do
    it "retrives Audit Log" do
      CLIENT.get_audit_log(TEST_GUILD, TEST_USER, limit: 5).should be_a(Discord::AuditLog)
    end
  end

  describe "#get_channel" do
    it "retrives Channel" do
      CLIENT.get_channel(TEST_CHANNEL).should be_a(Discord::Channel)
    end
  end

  describe "#modify_channel" do
    it "modifies Channel" do
      random_uuid = UUID.random.to_s
      CLIENT.modify_channel(TEST_CHANNEL, topic: random_uuid, reason: "Discord::REST #modify_channel modifies Channel").topic.should eq(random_uuid)
    end
  end

  mid = 0_u64
  describe "#get_channel_messages" do
    it "retrives messages form channel" do
      (m = CLIENT.get_channel_messages(TEST_CHANNEL, limit: 10)).should be_a(Array(Discord::Message))
      mid = m[0].id.value if m.size > 0
    end
  end

  describe "#get_channel_message" do
    it "retrives message from channel" do
      fail("could not retrive any message id") if mid == 0
      CLIENT.get_channel_message(TEST_CHANNEL, mid).should be_a(Discord::Message)
    end
  end

  avatar = ""
  describe "#get_user" do
    it "retrives User" do
      (user = CLIENT.get_user(TEST_USER)).should be_a(Discord::User)
      avatar = user.avatar_url(Discord::CDN::ExtraImageFormat::PNG, 512)
      HTTP::Client.get(avatar) do |response|
        unless response.success?
          fail("could not get the avatar of TEST_USER")
        end
        File.write "testUserAvatar.png", response.body_io
      end
    end
  end

  describe "#create_message" do
    it "sends a normal message" do
      CLIENT.create_message(TEST_CHANNEL, "Discord::REST #create_message sends a normal message\nRandom UUID: #{UUID.random}").should be_a(Discord::Message)
    end

    it "sends a simple embedded message" do
      CLIENT.create_message(TEST_CHANNEL, embeds: [Discord::Embed.new("Embed Title", description: "Discord::REST #create_message sends a simple embedded message", colour: 0xFF00FF)]).should be_a(Discord::Message)
    end

    it "sends file" do
      CLIENT.create_message(TEST_CHANNEL, content: "Discord::REST #create_message sends file", file: "testUserAvatar.png").should be_a(Discord::Message)
    end

    it "sends an embedded message with attachment" do
      thumb = Discord::EmbedThumbnail.new("attachment://testUserAvatar.png")
      author = Discord::EmbedAuthor.new("Embed Author", icon_url: "attachment://testUserAvatar.png")
      footer = Discord::EmbedFooter.new("Embed Footer", icon_url: "attachment://testUserAvatar.png")
      fields = [
        Discord::EmbedField.new("Embed Field #1", "Value"),
        Discord::EmbedField.new("Embed Field #2", "Eulav"),
      ]
      embed = Discord::Embed.new("Title", description: "Complex Embedded Message with Attachment", thumbnail: thumb, author: author, footer: footer, fields: fields, colour: 0x00FFFF)
      CLIENT.create_message(TEST_CHANNEL, content: "Discord::REST #create_message sends an embedded message with attachment", file: "testUserAvatar.png", embeds: [embed]).should be_a(Discord::Message)
    end
  end

  describe "#upload_file" do
    it "sends file spoiler" do
      (m = CLIENT.upload_file(TEST_CHANNEL, "Discord::REST #upload_file sends file spoiler", File.open("testUserAvatar.png"), "av.png", true)).should be_a(Discord::Message)
      mid = m.id.value
    end
  end

  describe "#create_reaction" do
    it "creates message reaction" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.create_reaction(TEST_CHANNEL, mid, "🆗")
    end
  end

  describe "#delete_own_reaction" do
    it "removes message reaction" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.create_reaction(TEST_CHANNEL, mid, "❌")
      CLIENT.delete_own_reaction(TEST_CHANNEL, mid, "❌")
    end
  end

  describe "#delete_user_reaction" do
    it "removes message reaction" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.create_reaction(TEST_CHANNEL, mid, "❌")
      CLIENT.delete_user_reaction(TEST_CHANNEL, mid, "❌", CLIENT.client_id)
    end
  end

  describe "#get_reactions" do
    it "retrives reactions information" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.create_reaction(TEST_CHANNEL, mid, "🆗")
      (r = CLIENT.get_reactions(TEST_CHANNEL, mid, "🆗")).should be_a(Array(Discord::User))
      r.size.should eq(1)
    end
  end

  describe "#delete_all_reactions" do
    it "removes all message reactions" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.create_reaction(TEST_CHANNEL, mid, "🆗")
      CLIENT.delete_all_reactions(TEST_CHANNEL, mid)
    end
  end

  describe "#delete_reaction" do
    it "removes message reaction" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.create_reaction(TEST_CHANNEL, mid, "🆗")
      CLIENT.delete_reaction(TEST_CHANNEL, mid, "🆗")
    end
  end

  bot_avatar = ""
  describe "#get_current_user" do
    it "retrives current User" do
      (user = CLIENT.get_current_user).should be_a(Discord::User)
      bot_avatar = user.avatar_url(Discord::CDN::ExtraImageFormat::PNG, 512)
      HTTP::Client.get(bot_avatar) do |response|
        unless response.success?
          fail("could not get the avatar of the bot")
        end
        File.write "testBotAvatar.png", response.body_io
      end
    end
  end

  describe "#edit_message" do
    it "modifies message contents" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.edit_message(TEST_CHANNEL, mid, content: "Discord::REST #edit_message modifies message contents").should be_a(Discord::Message)
    end

    it "modifies message by adding a file" do
      m = CLIENT.create_message(TEST_CHANNEL, content: "Discord::REST #edit_message modifies message by adding a file - Preparation stage")
      CLIENT.edit_message(TEST_CHANNEL, m.id, content: "Discord::REST #edit_message modifies message by adding a file", file: "testBotAvatar.png").should be_a(Discord::Message)
    end

    it "modifies sent embedded message" do
      embed = Discord::Embed.new("Embed Title - Preparation", description: "Discord::REST #edit_message modifies sent embedded message - Preparation stage", colour: 0xFF0000)
      m = CLIENT.create_message(TEST_CHANNEL, embeds: [embed])
      embed = Discord::Embed.new("Embed Title", description: "Discord::REST #edit_message modifies sent embedded message", colour: 0x00FF00)
      CLIENT.edit_message(TEST_CHANNEL, m.id, embeds: [embed]).should be_a(Discord::Message)
    end
  end

  describe "#delete_message" do
    it "removes a message" do
      m = CLIENT.create_message(TEST_CHANNEL, content: "Discord::REST #delete_message removes a message - Preparation stage")
      CLIENT.delete_message(TEST_CHANNEL, m.id.value)
    end
  end

  describe "#bulk_delete_messages" do
    it "removes sevral messages" do
      ids = [] of UInt64
      5.times { |i| ids << CLIENT.create_message(TEST_CHANNEL, content: "Discord::REST #bulk_delete_messages removes sevral messages - Preparation stage ##{i + 1}").id.value }
      CLIENT.bulk_delete_messages(TEST_CHANNEL, ids)
    end
  end

  describe "#edit_channel_permissions" do
    it "modifies channel permissions" do
      CLIENT.edit_channel_permissions(TEST_CHANNEL, CLIENT.client_id, Discord::OverwriteType::Member, allow: Discord::Permissions::All, reason: "Discord::REST #edit_channel_permissions modifies channel permissions")
    end
  end

  inv_code = ""
  describe "#create_channel_invite" do
    it "creates invite to a channel" do
      (i = CLIENT.create_channel_invite(TEST_CHANNEL, max_age: 60_u64, max_uses: 1_u32, reason: "Discord::REST #create_channel_invite creates invite to a channel")).should be_a(Discord::Invite)
      inv_code = i.code
    end
  end

  describe "#get_channel_invites" do
    it "retrives invites for channel" do
      CLIENT.get_channel_invites(TEST_CHANNEL).should be_a(Array(Discord::InviteMetadata))
    end
  end

  describe "#delete_channel_permission" do
    it "removes channel permissions" do
      CLIENT.delete_channel_permission(TEST_CHANNEL, CLIENT.client_id)
    end
  end

  describe "#trigger_typing_indicator" do
    it "triggers typing indicator" do
      CLIENT.trigger_typing_indicator(TEST_CHANNEL)
    end
  end

  describe "#pin_message" do
    it "pins message" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.pin_message(TEST_CHANNEL, mid, "Discord::REST #pin_message pins message")
    end
  end

  describe "#get_pinned_messages" do
    it "retrives a list of pinned messages" do
      mid = send_test_message(CLIENT, TEST_CHANNEL) if mid == 0
      CLIENT.pin_message(TEST_CHANNEL, mid)
      CLIENT.get_pinned_messages(TEST_CHANNEL).should be_a(Array(Discord::Message))
    end
  end

  describe "#unpin_message" do
    it "unpins message" do
      CLIENT.get_pinned_messages(TEST_CHANNEL).each do |m|
        CLIENT.unpin_message(TEST_CHANNEL, m.id)
      end
    end
  end

  describe "#create_guild_emoji" do
    it "created a guild custom emoji" do
      base = Base64.encode(File.read("testBotAvatar.png")).gsub("\n", "")
      CLIENT.create_guild_emoji(TEST_GUILD, "test_bot", "data:image/png;base64,#{base}", reason: "Discord::REST #create_guild_emoji created a guild custom emoji").should be_a(Discord::Emoji)
    end
  end

  describe "#list_guild_emojis" do
    it "retrives a list of custom guild emojis" do
      CLIENT.list_guild_emojis(TEST_GUILD).should be_a(Array(Discord::Emoji))
    end
  end

  describe "#get_guild_emoji" do
    it "retrive a custom guild emoji" do
      es = CLIENT.list_guild_emojis(TEST_GUILD)
      fail("no guild emojis") if es.size == 0
      CLIENT.get_guild_emoji(TEST_GUILD, es[0].id.not_nil!.value).should be_a(Discord::Emoji)
    end
  end

  describe "#modify_guild_emoji" do
    it "modifies a custom guild emoji" do
      es = CLIENT.list_guild_emojis(TEST_GUILD)
      fail("no guild emojis") if es.size == 0
      CLIENT.modify_guild_emoji(TEST_GUILD, es[0].id.not_nil!, name: "bot_test", reason: "Discord::REST #modify_guild_emoji modifies a custom guild emoji").should be_a(Discord::Emoji)
    end

    it "modifies a custom guild emoji with roles" do
      es = CLIENT.list_guild_emojis(TEST_GUILD)
      fail("no guild emojis") if es.size == 0
      CLIENT.modify_guild_emoji(TEST_GUILD, es[0].id.not_nil!, name: "t_bot", roles: nil, reason: "Discord::REST #modify_guild_emoji modifies a custom guild emoji with roles").should be_a(Discord::Emoji)
    end
  end

  describe "#delete_guild_emoji" do
    it "removes a custom guild emoji" do
      es = CLIENT.list_guild_emojis(TEST_GUILD)
      fail("no guild emojis") if es.size == 0
      CLIENT.delete_guild_emoji(TEST_GUILD, es[0].id.not_nil!)
    end
  end

  describe "#get_guild" do
    it "retrives Guild" do
      CLIENT.get_guild(TEST_GUILD, true).should be_a(Discord::Guild)
    end
  end

  describe "#get_guild_preview" do
    it "retrives Guild Preview" do
      CLIENT.get_guild_preview(TEST_GUILD).should be_a(Discord::GuildPreview)
    end
  end

  describe "#modify_guild" do
    it "modifies guild" do
      (g = CLIENT.modify_guild(TEST_GUILD, "Discord::REST #modify_guild modifies guild", preferred_locale: "en-GB", afk_channel_id: nil)).should be_a(Discord::Guild)
      g.preferred_locale.should eq("en-GB")
      g.afk_channel_id.should be_nil
    end
  end

  describe "#get_guild_channels" do
    it "retrive a list of channels" do
      CLIENT.get_guild_channels(TEST_GUILD).should be_a(Array(Discord::Channel))
    end
  end

  tcid = 0_u64
  describe "#create_guild_channel" do
    it "creates a guild channel" do
      message = "Discord::REST #create_guild_channel creates a guild channel"
      random_uuid = UUID.random.to_s
      (c = CLIENT.create_guild_channel(TEST_GUILD, random_uuid, Discord::ChannelType::GuildText, topic: message, reason: message)).should be_a(Discord::Channel)
      c.name.should eq(random_uuid)
      c.topic.should eq(message)
      tcid = c.id.value
    end
  end

  describe "#modify_guild_channel_positions" do
    it "moves guild channels" do
      fail("no channel was created by tests") if tcid == 0
      CLIENT.modify_guild_channel_positions(TEST_GUILD, [Discord::REST::ModifyChannelPositionPayload.new(tcid, position: 2)])
    end
  end

  describe "#delete_channel" do
    it "removes a guild channel" do
      fail("no channel was created by tests") if tcid == 0
      CLIENT.delete_channel(tcid)
    end
  end

  describe "#get_guild_member" do
    it "retrives Guild Member" do
      CLIENT.get_guild_member(TEST_GUILD, TEST_USER).should be_a(Discord::GuildMember)
    end
  end

  describe "#list_guild_members" do
    it "retrives a list of Guild Members" do
      CLIENT.list_guild_members(TEST_GUILD).should be_a(Array(Discord::GuildMember))
    end
  end

  describe "#search_guild_members" do
    it "searches for Guild Members" do
      user = CLIENT.get_current_user
      (m = CLIENT.search_guild_members(TEST_GUILD, user.username)).should be_a(Array(Discord::GuildMember))
      m[0].user.not_nil!.id.should eq(user.id)
    end
  end

  describe "#modify_current_user_nick" do
    it "modifies bots nickname" do
      CLIENT.modify_current_user_nick(TEST_GUILD, "TestBot##{Random::Secure.next_u.to_s[..5]}", "Discord::REST #modify_current_user_nick modifies bots nickname")
    end
  end

  describe "#get_guild_bans" do
    it "retrives Guild Bans" do
      CLIENT.get_guild_bans(TEST_GUILD).should be_a(Array(Discord::GuildBan))
    end
  end

  describe "#get_guild_roles" do
    it "retrives guild Roles" do
      CLIENT.get_guild_roles(TEST_GUILD).should be_a(Array(Discord::Role))
    end
  end

  trid = 0_u64
  describe "#create_guild_role" do
    it "creates a guild role" do
      name = UUID.random.to_s
      (r = CLIENT.create_guild_role(TEST_GUILD, name: name, mentionable: false, reason: "Discord::REST #create_guild_role creates a guild role")).should be_a(Discord::Role)
      r.name.should eq(name)
      trid = r.id.value
    end
  end

  describe "#modify_guild_role_positions" do
    it "moves role" do
      fail("no role was created by tests") if trid == 0
      CLIENT.modify_guild_role_positions(TEST_GUILD, [Discord::REST::ModifyRolePositionPayload.new(trid, 2)]).should be_a(Array(Discord::Role))
    end
  end

  describe "#modify_guild_role" do
    it "modifies guild role" do
      fail("no role was created by tests") if trid == 0
      CLIENT.modify_guild_role(TEST_GUILD, trid, mentionable: true, reason: "Discord::REST #modify_guild_role modifies guild role").should be_a(Discord::Role)
    end
  end

  describe "#add_guild_member_role" do
    it "gives a role to a guild member" do
      fail("no role was created by tests") if trid == 0
      CLIENT.add_guild_member_role(TEST_GUILD, TEST_USER, trid, "Discord::REST #add_guild_member_role gives a role to a guild member")
    end
  end

  describe "#remove_guild_member_role" do
    it "takes away a role from a guild member" do
      fail("no role was created by tests") if trid == 0
      CLIENT.remove_guild_member_role(TEST_GUILD, TEST_USER, trid)
    end
  end

  describe "#delete_guild_role" do
    it "removes guil role" do
      fail("no role was created by tests") if trid == 0
      CLIENT.delete_guild_role(TEST_GUILD, trid)
    end
  end

  describe "#get_guild_prune_count" do
    it "retrives guild prune count" do
      CLIENT.get_guild_prune_count(TEST_GUILD)
    end
  end

  describe "#get_guild_voice_regions" do
    it "retrives Voice Regions" do
      CLIENT.get_guild_voice_regions(TEST_GUILD).should be_a(Array(Discord::VoiceRegion))
    end
  end

  describe "#get_guild_invites" do
    it "retrives guild invites" do
      CLIENT.get_guild_invites(TEST_GUILD).should be_a(Array(Discord::InviteMetadata))
    end
  end

  describe "#get_guild_integrations" do
    it "retrives guild integrations" do
      CLIENT.get_guild_integrations(TEST_GUILD).should be_a(Array(Discord::Integration))
    end
  end

  describe "#get_guild_widget_settings" do
    it "retrives guild widget settings" do
      CLIENT.get_guild_widget_settings(TEST_GUILD).should be_a(Discord::GuildWidgetSettings)
    end
  end

  describe "#modify_guild_widget" do
    it "modifies guild widget settings" do
      CLIENT.modify_guild_widget(TEST_GUILD, enabled: true).should be_a(Discord::GuildWidgetSettings)
    end
  end

  describe "#get_guild_widget" do
    it "retrives guild widget" do
      CLIENT.get_guild_widget(TEST_GUILD).should be_a(Discord::GuildWidget)
    end
  end

  tcode = ""
  describe "#create_guild_templates" do
    it "creates a guild template from a guild" do
      name = UUID.random.to_s
      (t = CLIENT.create_guild_templates(TEST_GUILD, name, "Discord::REST #create_guild_templates creates a guild template from a guild")).should be_a(Discord::GuildTemplate)
      t.name.should eq(name)
      tcode = t.code
    end
  end

  describe "#get_guild_template" do
    it "retrives Guild Template" do
      fail("no guild template was created by tests") if tcode == ""
      CLIENT.get_guild_template(tcode).should be_a(Discord::GuildTemplate)
    end
  end

  describe "#get_guild_templates" do
    it "retrives guild templates" do
      CLIENT.get_guild_templates(TEST_GUILD).should be_a(Array(Discord::GuildTemplate))
    end
  end

  describe "#sync_guild_templates" do
    it "syncs guild template with the guild" do
      fail("no guild template was created by tests") if tcode == ""
      CLIENT.sync_guild_templates(TEST_GUILD, tcode).should be_a(Discord::GuildTemplate)
    end
  end

  describe "#modify_guild_templates" do
    it "modifies guild template" do
      fail("no guild template was created by tests") if tcode == ""
      CLIENT.modify_guild_templates(TEST_GUILD, tcode, description: "Discord::REST #modify_guild_templates modifies guild template").should be_a(Discord::GuildTemplate)
    end
  end

  describe "#delete_guild_templates" do
    it "removes guild template" do
      fail("no guild template was created by tests") if tcode == ""
      CLIENT.delete_guild_templates(TEST_GUILD, tcode)
    end
  end

  describe "#get_invite" do
    it "retrives invite" do
      fail("no invite was created by tests") if inv_code == ""
      CLIENT.get_invite(inv_code).should be_a(Discord::Invite)
    end
  end

  describe "#delete_invite" do
    it "deletes invite" do
      fail("no invite was created by tests") if inv_code == ""
      CLIENT.delete_invite(inv_code)
    end
  end

  describe "#modify_current_user" do
    it "modifies current user" do
      CLIENT.modify_current_user.should be_a(Discord::User)
    end
  end

  describe "#get_current_user_guilds" do
    it "retrives current users guilds" do
      CLIENT.get_current_user_guilds.should be_a(Array(Discord::PartialGuild))
    end
  end

  describe "#create_dm" do
    it "creates a direct messaging channel with the test user" do
      CLIENT.create_dm(TEST_USER).should be_a(Discord::PrivateChannel)
    end
  end

  describe "#get_user_connections" do
    it "retrives user connections" do
      CLIENT.get_user_connections.should be_a(Array(Discord::Connection))
    end
  end

  describe "#list_voice_regions" do
    it "retrives a list of voice regions" do
      CLIENT.list_voice_regions.should be_a(Array(Discord::VoiceRegion))
    end
  end

  twid = 0_u64
  token = ""
  describe "#create_webhook" do
    it "created a webhook" do
      name = UUID.random.to_s
      (w = CLIENT.create_webhook(TEST_CHANNEL, name)).should be_a(Discord::Webhook)
      w.name.should eq(name)
      twid = w.id.value
      token = w.token || ""
    end
  end

  describe "#get_channel_webhooks" do
    it "retrives webhooks for channel" do
      CLIENT.get_channel_webhooks(TEST_CHANNEL).should be_a(Array(Discord::Webhook))
    end
  end

  describe "#get_webhook" do
    it "retrives webhook" do
      fail("no webhook created by tests") if twid == 0
      CLIENT.get_webhook(twid).should be_a(Discord::Webhook)
    end

    it "retrives webhook with token" do
      fail("no webhook created by tests") if twid == 0
      CLIENT.get_webhook(twid, token).should be_a(Discord::Webhook)
    end
  end

  describe "#modify_webhook" do
    it "modifies webhook" do
      fail("no webhook created by tests") if twid == 0
      name = UUID.random.to_s
      (w = CLIENT.modify_webhook(twid, name: name)).should be_a(Discord::Webhook)
      w.name.should eq(name)
    end

    it "modifies webhook with token" do
      fail("no webhook created by tests") if twid == 0
      name = UUID.random.to_s
      (w = CLIENT.modify_webhook_with_token(twid, token, name: name)).should be_a(Discord::Webhook)
      w.name.should eq(name)
    end
  end

  twmid1 = twmid2 = twmid3 = twmid4 = 0_u64
  describe "#execute_webhook" do
    it "sends a normal message" do
      fail("no webhook created by tests") if twid == 0
      (m = CLIENT.execute_webhook(twid, token, "Discord::REST #execute_webhook sends a normal message\nRandom UUID: #{UUID.random}", wait: true)).should be_a(Discord::Message)
      twmid1 = m.not_nil!.id.value
    end

    it "sends a simple embedded message" do
      fail("no webhook created by tests") if twid == 0
      (m = CLIENT.execute_webhook(twid, token, embeds: [Discord::Embed.new("Embed Title", description: "Discord::REST #execute_webhook sends a simple embedded message", colour: 0xFF00FF)], wait: true)).should be_a(Discord::Message)
      twmid2 = m.not_nil!.id.value
    end

    it "sends file" do
      fail("no webhook created by tests") if twid == 0
      (m = CLIENT.execute_webhook(twid, token, content: "Discord::REST #execute_webhook sends file", file: "testUserAvatar.png", wait: true)).should be_a(Discord::Message)
      twmid3 = m.not_nil!.id.value
    end

    it "sends an embedded message with attachment" do
      fail("no webhook created by tests") if twid == 0
      thumb = Discord::EmbedThumbnail.new("attachment://testUserAvatar.png")
      author = Discord::EmbedAuthor.new("Embed Author", icon_url: "attachment://testUserAvatar.png")
      footer = Discord::EmbedFooter.new("Embed Footer", icon_url: "attachment://testUserAvatar.png")
      fields = [
        Discord::EmbedField.new("Embed Field #1", "Value"),
        Discord::EmbedField.new("Embed Field #2", "Eulav"),
      ]
      embed = Discord::Embed.new("Title", description: "Complex Embedded Message with Attachment", thumbnail: thumb, author: author, footer: footer, fields: fields, colour: 0x00FFFF)
      (m = CLIENT.execute_webhook(twid, token, content: "Discord::REST #execute_webhook sends an embedded message with attachment", file: "testUserAvatar.png", embeds: [embed], wait: true)).should be_a(Discord::Message)
      twmid4 = m.not_nil!.id.value
    end
  end

  describe "#get_webhook_message" do
    it "retrives webhook message" do
      fail("no webhook created by tests") if twid == 0
      CLIENT.get_webhook_message(twid, token, twmid1).should be_a(Discord::Message)
      CLIENT.get_webhook_message(twid, token, twmid2).should be_a(Discord::Message)
      CLIENT.get_webhook_message(twid, token, twmid3).should be_a(Discord::Message)
      CLIENT.get_webhook_message(twid, token, twmid4).should be_a(Discord::Message)
    end
  end

  describe "#edit_webhook_message" do
    it "modifies webhook message contents" do
      fail("no webhook created by tests") if twid == 0
      CLIENT.edit_webhook_message(twid, token, twmid1, content: "Discord::REST #edit_webhook_message modifies message contents").should be_a(Discord::Message)
    end

    it "modifies webhook message by adding a file" do
      fail("no webhook created by tests") if twid == 0
      CLIENT.edit_webhook_message(twid, token, twmid1, content: "Discord::REST #edit_webhook_message modifies message by adding a file", file: "testBotAvatar.png").should be_a(Discord::Message)
    end

    it "modifies embedded webhook message" do
      fail("no webhook created by tests") if twid == 0
      embed = Discord::Embed.new("Embed Title", description: "Discord::REST #edit_webhook_message modifies sent embedded message", colour: 0x00FF00)
      CLIENT.edit_webhook_message(twid, token, twmid2, embeds: [embed]).should be_a(Discord::Message)
    end
  end

  describe "#delete_webhook_message" do
    it "removes webhook message" do
      fail("no webhook created by tests") if twid == 0
      CLIENT.delete_webhook_message(twid, token, twmid3)
    end
  end

  describe "#delete_webhook" do
    it "removes webhook" do
      fail("no webhook created by tests") if twid == 0
      CLIENT.delete_webhook(twid)
    end
  end

  {% if env("APPLICATION") %}
  test_application = {{ env("APPLICATION") }}.to_u64

  tgapid = 0_u64
  tgapname = ""
  describe "#create_global_application_command" do
    it "creates a global application command" do
      tgapname = UUID.random.to_s[..20]
      description = "Discord::REST #create_global_application_command creates a global application command"
      (a = CLIENT.create_global_application_command(test_application, tgapname, description)).should be_a(Discord::ApplicationCommand)
      a.name.should eq(tgapname)
    end

    it "creates a global application command with options" do
      name = UUID.random.to_s[..20]
      description = "Discord::REST #create_global_application_command creates a global application command with options"
      options = [
        Discord::ApplicationCommandOption.new(UUID.random.to_s[..20], Discord::ApplicationCommandOptionType::String, "test 1"),
        Discord::ApplicationCommandOption.new(UUID.random.to_s[..20], Discord::ApplicationCommandOptionType::Integer, "test 2"),
      ]
      (a = CLIENT.create_global_application_command(test_application, name, description, options)).should be_a(Discord::ApplicationCommand)
      a.name.should eq(name)
      a.options.not_nil!.size.should eq(2)
      tgapid = a.id.value
    end
  end

  describe "#get_global_application_commands" do
    it "retrives global application commands" do
      CLIENT.get_global_application_commands(test_application).should be_a(Array(Discord::ApplicationCommand))
    end
  end

  describe "#get_global_application_command" do
    it "retrives a global application command" do
      fail("no application command was created by tests") if tgapid == 0
      CLIENT.get_global_application_command(test_application, tgapid).should be_a(Discord::ApplicationCommand)
    end
  end

  describe "#edit_global_application_command" do
    it "modifies global application command" do
      fail("no application command was created by tests") if tgapid == 0
      CLIENT.edit_global_application_command(test_application, tgapid, options: [] of Discord::ApplicationCommandOption).should be_a(Discord::ApplicationCommand)
    end
  end

  describe "#bulk_overwrite_global_application_commands" do
    it "modifies multiple global application commands" do
      fail("no application command was created by tests") if tgapname == ""
      CLIENT.bulk_overwrite_global_application_commands(test_application, [Discord::PartialApplicationCommand.new(tgapname, "TEST 1")]).should be_a(Array(Discord::ApplicationCommand))
    end
  end

  describe "#delete_global_application_command" do
    it "removes global application commands" do
      CLIENT.get_global_application_commands(test_application).each do |gap|
        CLIENT.delete_global_application_command(test_application, gap.id)
      end
    end
  end

  tapid = 0_u64
  tapname = ""
  describe "#create_guild_application_command" do
    it "creates a guild application command" do
      tapname = UUID.random.to_s[..20]
      description = "Discord::REST #create_guild_application_command creates a guild application command"
      (a = CLIENT.create_guild_application_command(test_application, TEST_GUILD, tapname, description)).should be_a(Discord::ApplicationCommand)
      a.name.should eq(tapname)
    end

    it "creates a guild application command with options" do
      name = UUID.random.to_s[..20]
      description = "Discord::REST #create_guild_application_command creates a guild application command with options"
      options = [
        Discord::ApplicationCommandOption.new(UUID.random.to_s[..20], Discord::ApplicationCommandOptionType::String, "test 1"),
        Discord::ApplicationCommandOption.new(UUID.random.to_s[..20], Discord::ApplicationCommandOptionType::Integer, "test 2"),
      ]
      (a = CLIENT.create_guild_application_command(test_application, TEST_GUILD, name, description, options)).should be_a(Discord::ApplicationCommand)
      a.name.should eq(name)
      a.options.not_nil!.size.should eq(2)
      tapid = a.id.value
    end
  end
  
  describe "#get_guild_application_commands" do
    it "retrives guild application commands" do
      CLIENT.get_guild_application_commands(test_application, TEST_GUILD).should be_a(Array(Discord::ApplicationCommand))
    end
  end

  describe "#get_guild_application_command" do
    it "retrives a guild application command" do
      fail("no application command was created by tests") if tapid == 0
      CLIENT.get_guild_application_command(test_application, TEST_GUILD, tapid).should be_a(Discord::ApplicationCommand)
    end
  end

  describe "#edit_guild_application_command" do
    it "modifies a guild application command" do
      fail("no application command was created by tests") if tapid == 0
      CLIENT.edit_guild_application_command(test_application, TEST_GUILD, tapid, options: [] of Discord::ApplicationCommandOption).should be_a(Discord::ApplicationCommand)
    end
  end

  describe "#bulk_overwrite_guild_application_command" do
    it "modifies multiple guild application commands" do
      fail("no application command was created by tests") if tapname == 0
      (a = CLIENT.bulk_overwrite_guild_application_command(test_application, TEST_GUILD, [Discord::PartialApplicationCommand.new(tapname, "TEST 1")])).should be_a(Array(Discord::ApplicationCommand))
      a.size.should eq(1)
      tapid = a[0].id.value
    end
  end

  describe "#get_guild_application_command_permissions" do
    it "retrives guild application command permissions" do
      CLIENT.get_guild_application_command_permissions(test_application, TEST_GUILD).should be_a(Array(Discord::GuildApplicationCommandPermissions))
    end
  end

  describe "#edit_application_command_permissions" do
    it "modifies a guild application command permissions" do
      fail("no application command was created by tests") if tapid == 0
      CLIENT.edit_application_command_permissions(test_application, TEST_GUILD, tapid, [Discord::ApplicationCommandPermissions.user(TEST_USER, false)])
    end
  end

  describe "#batch_edit_application_command_permissions" do
    it "modifies multiple guild application command permissions" do
      fail("no application command was created by tests") if tapid == 0
      CLIENT.batch_edit_application_command_permissions(test_application, TEST_GUILD, {tapid => [Discord::ApplicationCommandPermissions.user(TEST_USER, true)]})
    end
  end

  describe "#get_application_command_permissions" do
    it "retrives a guild application command permission" do
      fail("no application command was created by tests") if tapid == 0
      CLIENT.get_application_command_permissions(test_application, TEST_GUILD, tapid).should be_a(Discord::GuildApplicationCommandPermissions)
    end
  end

  describe "#delete_guild_application_command" do
    it "removes guild application commands" do
      CLIENT.get_guild_application_commands(test_application, TEST_GUILD).each do |ap|
        CLIENT.delete_guild_application_command(test_application, TEST_GUILD, ap.id)
      end
    end
  end
  {% end %}
end
