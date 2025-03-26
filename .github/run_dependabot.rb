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
commit = fetcher.commit

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
  ddependencies.select(&:top_level?).each do |dep|
    puts "Checking #{dep.name}..."
  
    # Se não há requirements ou se qualquer requirement estiver nil => SKIP
    if dep.requirements.nil? || dep.requirements.empty? ||
       dep.requirements.any? { |r| r[:requirement].nil? }
      puts "Skipping #{dep.name} - it has no valid requirement"
      next
    end
  
    # Crie o checker (só chegamos aqui se requirement não é nil)
    checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
      dependency: dep,
      dependency_files: files,
      credentials: credentials
    )
  
    # Verifica se pode atualizar
    # can_update =
    #   if checker.respond_to?(:updatable?)
    #     checker.updatable?
    #   elsif checker.respond_to?(:can_update?)
    #     checker.can_update?(requirements_to_unlock: :own)
    #   else
    #     false
    #   end
  
    # unless can_update
    #   puts "No updates available for #{dep.name}"
    #   next
    # end

    next if checker.up_to_date?

    requirements_to_unlock =
      if !checker.requirements_unlocked_or_can_be?
        if checker.can_update?(requirements_to_unlock: :none) then :none
        else :update_not_possible
        end
      elsif checker.can_update?(requirements_to_unlock: :own) then :own
      elsif checker.can_update?(requirements_to_unlock: :all) then :all
      else :update_not_possible
      end
  
    next if requirements_to_unlock == :update_not_possible

    puts "Updating #{dep.name}"
    updated_deps = checker.updated_dependencies(
      requirements_to_unlock: requirements_to_unlock
    )
  
    print "  - Updating #{dep.name} (from #{dep.version})…"
    update_files = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
      dependencies: updated_deps,
      dependency_files: files,
      credentials: credentials
    )

    updated_files = update_files.updated_dependency_files
  
    pr_creator = Dependabot::PullRequestCreator.new(
      source: source,
      base_commit: commit,
      dependencies: updated_deps,
      files: updated_files,
      credentials: credentials,
      pr_message: "Bump #{dep.name} to #{dep.version}",
      author_details: { name: "Dependabot", email: "no-reply@github.com" },
      label_language: true
    )

    pull_request = pr_creator.create
    puts " submitted"

    next unless pull_request
  end
  
else
  puts "No dependencies found"
end
