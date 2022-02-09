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
        description: "Increase/decrease per step (Default: 1)",
        min_value: 1,
        max_value: 10
      )
    ]
  )
)

commands.push(
  Discord::PartialApplicationCommand.new(
    name: "Greet",
    description: "",
    type: Discord::ApplicationCommandType::User
  )
)

commands.push(
  Discord::PartialApplicationCommand.new(
    name: "Upcase",
    description: "",
    type: Discord::ApplicationCommandType::Message
  )
)

commands.push(
  Discord::PartialApplicationCommand.new(
    name: "modal_test",
    description: "Show a sample modal"
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
    when "Greet"
      response = begin
        user = data.resolved.not_nil!.users.not_nil![data.target_id.not_nil!]
        Discord::InteractionResponse.message(
          ":wave: #{user.mention}"
        )
      rescue
        Discord::InteractionResponse.message(
          "Who am I supposed to greet!?"
        )
      end
      client.create_interaction_response(interaction.id, interaction.token, response)
    when "Upcase"
      response = begin
        message = data.resolved.not_nil!.messages.not_nil![data.target_id.not_nil!]
        Discord::InteractionResponse.message(
          message.content.upcase
        )
      rescue
        Discord::InteractionResponse.message(
          "What am I supposed to upcase!?"
        )
      end
      client.create_interaction_response(interaction.id, interaction.token, response)
    when "modal_test"
      response = Discord::InteractionResponse.modal(
        custom_id: "sample_modal",
        title: "Sample Modal",
        components: [
          Discord::ActionRow.new(
            Discord::TextInput.new("short", Discord::TextInputStyle::Short, "Short text field")
          ),
          Discord::ActionRow.new(
            Discord::TextInput.new("paragraph", Discord::TextInputStyle::Paragraph, "Long text field")
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
  elsif interaction.type.modal_submit?
    data = interaction.data.as(Discord::ModalSubmitInteractionData)
    
    response_text = String.build do |str|
      data.components.each do |row|
        row.components.each do |component|
          str << "#{component.custom_id}: #{component.value}\n" if component.is_a?(Discord::TextInput)
        end
      end
    end
    response = Discord::InteractionResponse.message(
      response_text
    )
    client.create_interaction_response(interaction.id, interaction.token, response)
  end
end

client.run
