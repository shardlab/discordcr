# This example bot demonstrates interaction-related features
# such as Application Commands and Message Components.
#
# For more information on interactions in general, see
# https://discord.com/developers/docs/interactions/receiving-and-responding#interactions-and-bot-users

require "../src/discordcr"

# Make sure to replace this fake data with actual data when running.
client = Discord::Client.new(token: "Bot MjI5NDU5NjgxOTU1NjUyMzM3.Cpnz31.GQ7K9xwZtvC40y8MPY3eTqjEIXm", client_id: 229459681955652337_u64)

# Making an array of commands with `PartialApplicationCommand`
# to register multiple commands altogether.
# You may want to separate these procedures into a separate program to avoid
# registering the same many commands each time you start the bot.

commands = [] of Discord::PartialApplicationCommand

commands.push(
  Discord::PartialApplicationCommand.new(
    name: "animal",
    description: "Reacts with the type of animal you select",
    options: [
      Discord::ApplicationCommandOption.string(
        name: "animal_type",
        description: "The type of animal you want to hear from",
        required: true,
        choices: [
          Discord::ApplicationCommandOptionChoice.new(
            "dog", "woof!"
          ),
          Discord::ApplicationCommandOptionChoice.new(
            "cat", "meow"
          )
        ]
      )
    ]
  )
)

commands.push(
  Discord::PartialApplicationCommand.new(
    name: "counter",
    description: "Show a step-up/step-down counter",
    options: [
      Discord::ApplicationCommandOption.integer(
        name: "step",
        description: "Increase/decrease per step (Default: 1)"
      )
    ]
  )
)

# You can also register one by one with `#create_global_application_command`
client.bulk_overwrite_global_application_commands(commands)

# Handle interactions
client.on_interaction_create do |interaction|
  if interaction.type.application_command?
    data = interaction.data.as(Discord::ApplicationCommandInteractionData)

    case data.name
    when "animal"
      response = Discord::InteractionResponse.message(
        data.options.not_nil!.first.value.to_s
      )
      client.create_interaction_response(interaction.id, interaction.token, response)
    when "counter"
      step = data.options.try(&.first.value) || 1
      response = Discord::InteractionResponse.message(
        "0",
        components: [
          Discord::ActionRow.new(
            Discord::Button.new(Discord::ButtonStyle::Primary, "-", custom_id: "sub:#{step}"),
            Discord::Button.new(Discord::ButtonStyle::Primary, "+", custom_id: "add:#{step}")
          )
        ]
      )
      client.create_interaction_response(interaction.id, interaction.token, response)
    end
  elsif interaction.type.message_component?
    data = interaction.data.as(Discord::MessageComponentInteractionData)

    key, value = data.custom_id.split(":")
    count = interaction.message.not_nil!.content.to_i
    case key
    when "add"
      count += value.to_i
    when "sub"
      count -= value.to_i
    end

    response = Discord::InteractionResponse.update_message(
      count.to_s
    )
    client.create_interaction_response(interaction.id, interaction.token, response)
  end
end

client.run
