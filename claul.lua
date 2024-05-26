local os = require("os")
local http = require("socket.http")
local lfs = require("lfs")
local dotenv = require("dotenv")

dotenv.config()

local openai_api_key = os.getenv("OPENAI_API_KEY")

local INSTRUCTIONS = "<<PUT THE PROMPT HERE>>"

local TEMPERATURE = 0.5
local MAX_TOKENS = 500
local FREQUENCY_PENALTY = 0
local PRESENCE_PENALTY = 0.6
local MAX_CONTEXT_QUESTIONS = 10

local function get_response(instructions, previous_questions_and_answers, new_question)
    local messages = {
        { role = "system", content = instructions },
    }

    for i = math.max(1, #previous_questions_and_answers - MAX_CONTEXT_QUESTIONS + 1), #previous_questions_and_answers do
        local question, answer = unpack(previous_questions_and_answers[i])
        table.insert(messages, { role = "user", content = question })
        table.insert(messages, { role = "assistant", content = answer })
    end

    table.insert(messages, { role = "user", content = new_question })

    local response_body, status_code, response_headers, status = http.request {
        url = "https://api.openai.com/v1/chat/completions",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. openai_api_key,
        },
        source = ltn12.source.string(
            json.encode {
                model = "gpt-3.5-turbo",
                messages = messages,
                temperature = TEMPERATURE,
                max_tokens = MAX_TOKENS,
                top_p = 1,
                frequency_penalty = FREQUENCY_PENALTY,
                presence_penalty = PRESENCE_PENALTY,
            }
        ),
        sink = ltn12.sink.table(response_body_table),
    }

    if status_code ~= 200 then
        return "Error: " .. status_code .. " " .. table.concat(response_body_table)
    end

    local response_data = json.decode(table.concat(response_body_table))
    return response_data.choices[1].message.content
end

local function get_moderation(question)
    local errors = {
        hate = "Content that expresses, incites, or promotes hate based on race, gender, ethnicity, religion, nationality, sexual orientation, disability status, or caste.",
        ["hate/threatening"] = "Hateful content that also includes violence or serious harm towards the targeted group.",
        ["self-harm"] = "Content that promotes, encourages, or depicts acts of self-harm, such as suicide, cutting, and eating disorders.",
        sexual = "Content meant to arouse sexual excitement, such as the description of sexual activity, or that promotes sexual services (excluding sex education and wellness).",
        ["sexual/minors"] = "Sexual content that includes an individual who is under 18 years old.",
        violence = "Content that promotes or glorifies violence or celebrates the suffering or humiliation of others.",
        ["violence/graphic"] = "Violent content that depicts death, violence, or serious physical injury in extreme graphic detail.",
    }

    local response_body, status_code, response_headers, status = http.request {
        url = "https://api.openai.com/v1/moderations",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. openai_api_key,
        },
        source = ltn12.source.string(
            json.encode {
                input = question,
            }
        ),
        sink = ltn12.sink.table(response_body_table),
    }

    if status_code ~= 200 then
        return { "Error: " .. status_code .. " " .. table.concat(response_body_table) }
    end

    local response_data = json.decode(table.concat(response_body_table))
    if response_data.results[1].flagged then
        local result = {}
        for category, error in pairs(errors) do
            if response_data.results[1].categories[category] then
                table.insert(result, error)
            end
        end
        return result
    end

    return nil
end

local function main()
    os.execute(os.getenv("COMSPEC") and "cls" or "clear")
    local previous_questions_and_answers = {}

    while true do
        io.write(string.format("%c[%dm%s%c[%dm", 27, 32, "What can I get you?: ", 27, 0))
        local new_question = io.read()

        local errors = get_moderation(new_question)
        if errors then
            print(string.format("%c[%dm%s%c[%dm", 27, 31, "Sorry, you're question didn't pass the moderation check:", 27, 0))
            for _, error in ipairs(errors) do
                print(error)
            end
            goto continue
        end

        local response = get_response(INSTRUCTIONS, previous_questions_and_answers, new_question)

        table.insert(previous_questions_and_answers, { new_question, response })

        print(string.format("%c[%dm%s %c[%dm%s", 27, 36, "Here you go:", 27, 0, response))

        ::continue::
    end
end

main()