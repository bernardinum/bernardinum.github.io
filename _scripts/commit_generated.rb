def run_cmd(cmd)
  ok = system(cmd)
  raise "Command failed: #{cmd}" unless ok
end

def git_has_changes?(paths)
  # jeśli są zmiany w tych ścieżkach, git diff zwróci exit code 1
  system("git diff --quiet -- #{paths.join(' ')}")
  $?.exitstatus != 0
end

def git_commit_and_push(paths, message)
  # ustaw autora (w Actions inaczej czasem odmawia)
  run_cmd(%q(git config user.name "github-actions[bot]"))
  run_cmd(%q(git config user.email "github-actions[bot]@users.noreply.github.com"))

  run_cmd("git add #{paths.join(' ')}")

  # commit może nic nie zrobić -> zabezpieczenie
  run_cmd(%Q(git commit -m "#{message}")) if git_has_changes?(paths)

  # push na aktualną gałąź
  run_cmd("git push")
end

# --- AUTO-COMMIT w CI ---
if ENV['GITHUB_ACTIONS'] == 'true' && ENV['BERNARDINUM_AUTO_COMMIT'] == '1'
  paths = ['_data/news.json', '_posts']
  msg = "chore: update news.json and generated posts"
  if git_has_changes?(paths)
    puts "INFO: Wykryto zmiany w #{paths.join(', ')} – robię commit i push..."
    git_commit_and_push(paths, msg)
  else
    puts "INFO: Brak zmian do commitu."
  end
end
