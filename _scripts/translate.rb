#!/usr/bin/env ruby
# frozen_string_literal: true

# Script para traduzir posts do blog usando DeepSeek API
# Uso: ruby _scripts/translate.rb _posts/2026-06-21-meu-post.md
#
# Requer: DEEPSEEK_API_KEY no ambiente

require "net/http"
require "json"
require "yaml"
require "time"

POSTS_DIR = File.join(__dir__, "..", "_posts")

def translate_post(file_path)
  content = File.read(file_path)
  parts = content.split("---", 3)
  raise "Formato inválido" unless parts.size >= 3

  front_matter = YAML.safe_load(parts[1]) || {}
  body = parts[2]&.strip || ""

  source_lang = front_matter["lang"] || "pt"
  target_lang = source_lang == "pt" ? "en" : "pt"

  prompt = <<~PROMPT
    Traduza o seguinte post de blog de #{source_lang == "pt" ? "português" : "inglês"} para #{target_lang == "pt" ? "português" : "inglês"}.

    Mantenha o formato Markdown, blocos de código, links e formatação intactos.
    Traduza também o título, description e tags.

    Responda APENAS com um JSON neste formato exato:
    {
      "title": "Título traduzido",
      "description": "Descrição traduzida",
      "tags": ["tag1", "tag2"],
      "body": "Conteúdo traduzido em Markdown"
    }

    Título original: #{front_matter["title"]}
    Descrição original: #{front_matter["description"]}
    Tags originais: #{(front_matter["tags"] || []).join(", ")}
    Conteúdo:
    #{body}
  PROMPT

  response = call_deepseek(prompt)
  result = JSON.parse(response)

  new_date = Time.now.strftime("%Y-%m-%d")
  new_slug = result["title"]
    .downcase
    .gsub(/[^a-z0-9\s-]/, "")
    .gsub(/\s+/, "-")
    .gsub(/-+/, "-")
    .strip
    .slice(0, 80)
    .sub(/-$/, "")

  new_categories = target_lang
  new_file = File.join(POSTS_DIR, "#{new_date}-#{new_slug}.md")

  new_front = {
    "title" => result["title"],
    "description" => result["description"],
    "date" => new_date,
    "categories" => [new_categories],
    "tags" => result["tags"],
    "lang" => target_lang,
    "lang_ref" => front_matter["lang_ref"] || new_slug
  }

  File.write(new_file, "#{new_front.to_yaml}---\n#{result['body']}\n")
  puts "✓ Criado: #{new_file}"
  puts "  #{source_lang.upcase} → #{target_lang.upcase}"
rescue => e
  puts "✗ Erro: #{e.message}"
  exit 1
end

def call_deepseek(prompt)
  api_key = ENV["DEEPSEEK_API_KEY"] || raise("DEEPSEEK_API_KEY não definida")

  uri = URI("https://api.deepseek.com/v1/chat/completions")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request["Authorization"] = "Bearer #{api_key}"

  request.body = {
    model: "deepseek-chat",
    messages: [{ role: "user", content: prompt }],
    temperature: 0.3,
    max_tokens: 4096
  }.to_json

  response = http.request(request)
  body = JSON.parse(response.body)

  body.dig("choices", 0, "message", "content")
    .gsub(/^```json\s*/i, "")
    .gsub(/```\s*$/, "")
    .strip
end

abst = "Usage: ruby _scripts/translate.rb _posts/YYYY-MM-DD-titulo.md"
file = ARGV[0] || abort(abst)
abst abst unless File.exist?(file)
translate_post(file)
