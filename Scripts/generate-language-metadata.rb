#!/usr/bin/env ruby
# frozen_string_literal: true

# Audits the repository metadata table against the pinned GitHub Linguist
# languages.yml. Usage:
#   ruby Scripts/generate-language-metadata.rb /path/to/languages.yml

require "json"
require "yaml"

PIN = "821c1654e37491f53842efe398da2d5b1e175899"
NAMES = {
  "armasm" => "Assembly", "bash" => "Shell", "cpp" => "C++",
  "csharp" => "C#", "dos" => "Batchfile", "fsharp" => "F#",
  "graphql" => "GraphQL", "ini" => "INI", "javascript" => "JavaScript",
  "makefile" => "Makefile", "markdown" => "Markdown", "objectivec" => "Objective-C",
  "plaintext" => "Text", "powershell" => "PowerShell", "protobuf" => "Protocol Buffer",
  "r" => "R", "shell" => "ShellSession", "terraform" => "HCL",
  "typescript" => "TypeScript", "vim" => "Vim Script", "xml" => "HTML",
}.freeze

source = YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false)
rows = NAMES.sort.to_h do |highlightkit, linguist|
  entry = source.fetch(linguist)
  [highlightkit, {
    "linguist_name" => linguist,
    "extensions" => Array(entry["extensions"]).map { |ext| ext.delete_prefix(".").downcase },
    "filenames" => Array(entry["filenames"]).map(&:downcase),
    "interpreters" => Array(entry["interpreters"]).map(&:downcase),
  }]
end

puts JSON.pretty_generate({ "linguist_commit" => PIN, "languages" => rows })
