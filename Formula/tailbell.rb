# Homebrew formula for tailbell.
#
#   brew tap jackiectl/tailbell https://github.com/jackiectl/tailbell
#   brew install --HEAD tailbell
#
# HEAD-only on purpose. A stable bottle needs a tagged tarball and its sha256,
# and inventing either before the tag exists would put a checksum in this file
# that matches nothing. packaging/release.sh fills both in at tag time; until
# then --HEAD installs the same tree a git clone gives you.
#
# The formula deliberately does not register hooks or start anything. A package
# manager that edits ~/.claude/settings.json behind your back is the sort of
# surprise this project exists to avoid — `tailbell install` is a separate,
# visible step, and the caveats below say so.
class Tailbell < Formula
  desc "Desktop notifications when Claude Code finishes or needs you, including over SSH on an HPC cluster"
  homepage "https://github.com/jackiectl/tailbell"
  head "https://github.com/jackiectl/tailbell.git", branch: "main"
  license "MIT"

  # No dependencies, and that is the guarantee rather than an oversight: bash,
  # ssh, python3, osascript and jq are all either in the base system or already
  # required on the agent host. See docs/architecture.md.

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/tailbell"
  end

  def caveats
    <<~EOS
      Nothing has been registered yet. To finish setting up this machine:

        tailbell install        # this side
        tailbell doctor --test  # check every link, end to end

      On a cluster, the agent side needs its own copy — Claude Code reads the
      filesystem of the machine it runs on:

        tailbell deploy <your-cluster-alias>

      No third-party service is required, and none is configured by default.
    EOS
  end

  test do
    assert_match "tailbell", shell_output("#{bin}/tailbell help")
    system bin/"tailbell", "version"
  end
end
