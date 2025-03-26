require "dependabot/github_actions"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/source"

respo_name = ENV["repo_source"]
respo_branch = ENV["branch_source"]

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

package_manager = "github_actions"

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
puts "Dependencies found: #{ dependencies.count }"

if dependencies.respond_to?(:each)
  dependencies.each do |dep|
    if dep.requirements.nil? || !dep.requirements.is_a?(Array)
      puts "No requirements found for #{ dep.name }"
      next
    end

    puts "Checker for #{ dep.name }"
    checker = Dependabot:: UpdateCheckers.for_package_manager(package_manager).new(
      dependency: dep,
      dependency_files: files,
      credentials: credentials 
    )

    if checker.respond_to?(:updatable?)
      next unless checker.updatable?
    elsif checker.respond_to?(:can_update?)
      can_update = checker.can_update?(requirements_to_unlock: :own)
      next unless can_update
    else
      puts "Checker not found"
    end

    puts "Check update dependencies for #{ dep.name }"
    update_files = Dependabot::FileUpadaters.for_package_manager(package_manager).new(
      dependencies: [dep],
      dependency_files: files,
      credentials: credentials
    ).updated_dependency_files

    puts "Create a PR for #{ dep.name }"
    Dependabot::PullRequestCreator.new(
      source: source,
      base_commit: fetcher.commit,
      dependencies: [dep],
      files: update_files,
      credentials: credentials,
      pr_message: "Bump #{ dep.name } to #{ dep.version }"
    ).create

  end
else
  puts "No dependencies found"
end



  
