require "sorbet-runtime"
require "dependabot/github_actions"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/source"
require "dependabot/npm_and_yarn"
require "pp"

repo_name = ENV["repo_source"]
repo_branch = ENV["branch_source"]
ecosystem = ENV["ecosystem"]

source = Dependabot::Source.new(
  provider: "github",
  repo: repo_name,
  branch: repo_branch,
  directory: "/"
)

credentials = [{
  "type" => "git_source",
  "host" => "github.com",
  "username" => ENV["GH_USER"],
  "password" => ENV["GH_PASS"]
}]

package_manager = ecosystem

fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials
)

files = fetcher.files
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials
)

files.each { |f| puts "- #{f.name}" }

dependencies = parser.parse
puts "Dependencies found: #{dependencies.count}"

# Helper para extrair versão ou ref
def requirement_string(dep)
  req = dep.requirements&.first
  return nil if req.nil?

  req[:requirement] || req.dig(:source, :ref) || "N/A"
end

dependencies.each do |dep|
  puts "=========="
  puts "📦 #{dep.name}"
  puts "  📌 Version: #{dep.version}"
  puts "  📄 File: #{dep.requirements&.first&.dig(:file) || 'N/A'}"
  puts "  🔖 Declared as: #{requirement_string(dep)}"
end

if dependencies.respond_to?(:each)
  dependencies.each do |dep|
    puts "Checking #{dep.name}..."
  
    if dep.requirements.nil? || dep.requirements.empty?
      puts "Skipping #{dep.name} - no requirements"
      next
    end
  
    first_req = dep.requirements.first
    requirement = first_req[:requirement]
    ref = first_req.dig(:source, :ref)
  
    if requirement.nil? && ref.nil?
      puts "Skipping #{dep.name} - neither requirement nor ref is present"
      next
    end
  
    checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
      dependency: dep,
      dependency_files: files,
      credentials: credentials
    )
  
    can_update =
      if checker.respond_to?(:updatable?)
        checker.updatable?
      elsif checker.respond_to?(:can_update?)
        checker.can_update?(requirements_to_unlock: :own)
      else
        false
      end
  
    unless can_update
      puts "No updates available for #{dep.name}"
      next
    end
  
    puts "Updating #{dep.name}"
  
    update_files = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
      dependencies: [dep],
      dependency_files: files,
      credentials: credentials
    ).updated_dependency_files
  
    Dependabot::PullRequestCreator.new(
      source: source,
      base_commit: fetcher.commit,
      dependencies: [dep],
      files: update_files,
      credentials: credentials,
      pr_message: "Bump #{dep.name} to #{dep.version}"
    ).create
  end
else
  puts "No dependencies found"
end
