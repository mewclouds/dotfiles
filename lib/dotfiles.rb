# frozen_string_literal: true

require "rbconfig"

module Dotfiles
  module_function

  def run
    puts "Dotfiles orchestrator"
    puts "Platform: #{platform}"
  end

  def platform
    host_os = RbConfig::CONFIG.fetch("host_os")
    platform_name = case host_os
    when /mswin|mingw|cygwin/
      "windows"
    when /linux/
      "linux"
    else
      "unknown"
    end

    "#{platform_name} (#{host_os})"
  end
end
