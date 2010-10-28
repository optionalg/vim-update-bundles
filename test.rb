require 'rubygems'
require 'minitest/unit'
require 'tempfile'
require 'tmpdir'
MiniTest::Unit.autorun

# todo: test that tagstr works (branch, tag, and sha1)
#   also switching from a branch/tag/sha to master and back.
#   also with submodules
# todo: test BUNDLE-COMMAND
# todo: test removing bundles multiple times.

# This is actually functional testing the updater since we call
# the executable directly.  We just use minitest for the helpers
# and output.

class TestUpdater < MiniTest::Unit::TestCase
  def prepare_test
    # creates a tmpdir to run the test in then yields to the test
    Dir.mktmpdir('vimtest-') do |tmpdir|
      create_mock_files tmpdir
      Dir.mkdir "#{tmpdir}/home"
      ENV['HOME']="#{tmpdir}/home"
      ENV['TESTING']='1'
      yield "#{tmpdir}/home"
    end
  end

  def write_file base, path, contents
    File.open(File.join(base, path), 'w') { |f| f.write contents }
  end

  def create_mock_files tmpdir
    # create local mocks for the files would download, saves net traffic and test time.
    write_file tmpdir, "pathogen",      "\" PATHOGEN SCRIPT"
    write_file tmpdir, "starter-vimrc", "\" STARTER VIMRC"
    @starter_urls = "starter_url='#{tmpdir}/starter-vimrc' pathogen_url='#{tmpdir}/pathogen'"
  end

  def create_mock_repo name
    Dir.mkdir name
    Dir.chdir name do
      `git init`
      write_file name, "first", "first"
      `git add first`
      `git commit -q -m first`
    end
  end

  def update_mock_repo name, update
    Dir.chdir name do
      write_file name, update, update
      `git add '#{update}'`
      `git commit -q -m '#{update}'`
    end
  end

  def check_tree base, dotvim, vimrc
    # makes sure that the dir looks like a plausible vim installation
    assert test ?l, "#{base}/.vimrc"
    assert_equal File.readlink("#{base}/.vimrc"), "#{base}/#{vimrc}"
    assert test ?f, "#{base}/#{vimrc}"
    assert test ?f, "#{base}/#{dotvim}/autoload/pathogen.vim"
  end


  def test_standard_run
    # creates a starter environment then updates a few times
    prepare_test do |tmpdir|
      `./vim-update-bundles #{@starter_urls}`
      check_tree tmpdir, ".vim", ".vim/vimrc"

      # make sure docs are populated when we do an empty update
      `./vim-update-bundles`
      assert test ?f, "#{tmpdir}/.vim/doc/bundles.txt"
      assert test ?d, "#{tmpdir}/.vim/bundle"
      assert_equal ['.', '..'], Dir.open("#{tmpdir}/.vim/bundle") { |d| d.sort }

      # add a repo
      create_mock_repo "#{tmpdir}/repo"
      write_file tmpdir, ".vim/vimrc", "\" BUNDLE: #{tmpdir}/repo"
      `./vim-update-bundles`
      assert_equal ['.', '..', 'repo'], Dir.open("#{tmpdir}/.vim/bundle") { |d| d.sort }
      repo = "#{tmpdir}/.vim/bundle/repo"  # the local repo, not the origin
      assert test ?f, "#{repo}/first"
      assert_equal 1, File.read("#{repo}/.git/info/exclude").scan("doc/tags").count

      # pull some upstream changes
      update_mock_repo "#{tmpdir}/repo", "second"
      `./vim-update-bundles`
      assert test ?f, "#{tmpdir}/.vim/bundle/repo/second"
      assert_equal 1, File.read("#{repo}/.git/info/exclude").scan("doc/tags").count

      # remove the repo
      write_file tmpdir, ".vim/vimrc", ""
      `./vim-update-bundles`
      assert !test(?d, repo)
    end
  end


  def test_submodule_run
    # creates a starter environment using submodules
    prepare_test do |tmpdir|
      `./vim-update-bundles #{@starter_urls}`
      check_tree tmpdir, ".vim", ".vim/vimrc"
      Dir.chdir("#{tmpdir}/.vim") { `git init` }

      # add submodule
      create_mock_repo "#{tmpdir}/repo"

      File.open("#{tmpdir}/.vim-update-bundles.conf", 'w') { |f|
        f.write "submodule = true"
      }
      write_file tmpdir, ".vim/vimrc", "\" BUNDLE: #{tmpdir}/repo"

      `./vim-update-bundles`
      assert_equal ['.', '..', 'repo'], Dir.open("#{tmpdir}/.vim/bundle") { |d| d.sort }
      repo = "#{tmpdir}/.vim/bundle/repo"  # the local repo, not the origin
      assert test ?f, "#{repo}/first"
      assert test ?f, "#{tmpdir}/.vim/.gitmodules"
      assert_equal 1, File.read("#{repo}/.git/info/exclude").scan("doc/tags").count

      # pull some upstream changes
      update_mock_repo "#{tmpdir}/repo", "second"
      `./vim-update-bundles`
      assert test ?f, "#{tmpdir}/.vim/bundle/repo/second"

      # remove the repo
      write_file tmpdir, ".vim/vimrc", ""
      `./vim-update-bundles`
      assert !test(?d, repo)
    end
  end


  def test_create_dotfile_environment
    prepare_test do |tmpdir|
      Dir.mkdir "#{tmpdir}/.dotfiles"
      `./vim-update-bundles #{@starter_urls}`
      check_tree tmpdir, '.dotfiles/vim', '.dotfiles/vimrc'
    end
  end


  def test_create_custom_vimrc_environment
    prepare_test do |tmpdir|
      Dir.mkdir "#{tmpdir}/mydots"
      `./vim-update-bundles #{@starter_urls} vimrc='#{tmpdir}/mydots/vim rc'`
      check_tree tmpdir, '.vim', 'mydots/vim rc'
    end
  end


  def test_create_custom_conffile_environment
    prepare_test do |tmpdir|
      Dir.mkdir "#{tmpdir}/parent"
      Dir.mkdir "#{tmpdir}/parent/child"
      File.open("#{tmpdir}/.vim-update-bundles.conf", 'w') { |f|
        f.write "vimrc = '#{tmpdir}/parent/child/vv zz'"
      }
      `./vim-update-bundles #{@starter_urls}`
      check_tree tmpdir, '.vim', 'parent/child/vv zz'
    end
  end


  # def test_update_standard_environment
    # skip "needs work"
  # end
end
