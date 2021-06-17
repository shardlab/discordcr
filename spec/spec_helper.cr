require "spec"
require "uuid"
require "../src/discordcr.cr"

def send_test_message(client, channel_id) : UInt64
  CLIENT.create_message(channel_id, content: "Test message").id.value
end
