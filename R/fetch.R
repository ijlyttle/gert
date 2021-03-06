#' Push and pull
#'
#' Functions to connect with a git server (remote) to fetch or push changes.
#' The 'credentials' package is used to handle authentication, the
#' [credentials vignette](https://docs.ropensci.org/credentials/articles/intro.html)
#' explains the various authentication methods for SSH and HTTPS remotes.
#'
#' Use [git_fetch()] and [git_push()] to sync a local branch with a remote
#' branch. Here [git_pull()] is a wrapper for [git_fetch()] which then tries to
#' [fast-forward][git_branch_fast_forward()] the local branch after fetching.
#'
#' @export
#' @family git
#' @name git_fetch
#' @rdname git_fetch
#' @inheritParams git_open
#' @useDynLib gert R_git_remote_fetch
#' @param remote Optional. Name of a remote listed in [git_remote_list()]. If
#'   unspecified and the current branch is already tracking branch a remote
#'   branch, that remote is honored. Otherwise, defaults to `origin`.
#' @param refspec string with mapping between remote and local refs. Default
#' uses the default refspec from the remote, which usually fetches all branches.
#' @param mirror use the `--mirror` flag
#' @param bare use the `--bare` flag
#' @param force use the `--force` flag
#' @param prune delete tracking branches that no longer exist on the remote, or
#' are not in the refspec (such as pull requests).
git_fetch <- function(remote = NULL, refspec = NULL, password = askpass, ssh_key = NULL,
                      prune = FALSE, verbose = interactive(), repo = '.'){
  repo <- git_open(repo)
  info <- git_info(repo)
  if(!length(remote))
    remote <- info$remote
  remote <- as.character(remote)
  if(!length(remote) || is.na(remote)){
    if(is.na(match("origin", git_remote_list(repo = repo)$name))){
      stop("No remote is set for this branch")
    } else {
      inform("No remote set for this branch, using default remote 'origin'")
      remote <- "origin"
    }
  }
  refspec <- as.character(refspec)
  prune <- as.logical(prune)
  verbose <- as.logical(verbose)
  host <- remote_to_host(repo, remote)
  key_cb <- make_key_cb(ssh_key, host = host, password = password)
  cred_cb <- make_cred_cb(password = password, verbose = verbose)
  .Call(R_git_remote_fetch, repo, remote, refspec, key_cb, cred_cb, prune, verbose)
  git_repo_path(repo)
}

#' @export
#' @rdname git_fetch
#' @useDynLib gert R_git_remote_ls
git_remote_ls <- function(remote = NULL, password = askpass, ssh_key = NULL,
                                   verbose = interactive(), repo = '.'){
  repo <- git_open(repo)
  info <- git_info(repo)
  if(!length(remote))
    remote <- info$remote
  remote <- as.character(remote)
  if(!length(remote) || is.na(remote)){
    if(is.na(match("origin", git_remote_list(repo = repo)$name))){
      stop("No remote is set for this branch")
    } else {
      inform("No remote set for this branch, using default remote 'origin'")
      remote <- "origin"
    }
  }
  verbose <- as.logical(verbose)
  host <- remote_to_host(repo, remote)
  key_cb <- make_key_cb(ssh_key, host = host, password = password)
  cred_cb <- make_cred_cb(password = password, verbose = verbose)
  .Call(R_git_remote_ls, repo, remote, key_cb, cred_cb, verbose)
}

#' @export
#' @rdname git_fetch
#' @param set_upstream change the branch default upstream to `remote`.
#' If `NULL`, this will set the branch upstream only if the push was
#' successful and if the branch does not have an upstream set yet.
#' @useDynLib gert R_git_remote_push
git_push <- function(remote = NULL, refspec = NULL, set_upstream = NULL,
                     password = askpass, ssh_key = NULL, mirror = FALSE,
                     force = FALSE, verbose = interactive(), repo = '.'){
  repo <- git_open(repo)
  info <- git_info(repo)
  verbose <- as.logical(verbose)

  if(!length(remote))
    remote <- info$remote

  remote <- as.character(remote)

  if(!length(remote) || is.na(remote)){
    if(is.na(match("origin", git_remote_list(repo = repo)$name))){
      stop("No remote is set for this branch")
    } else {
      if (verbose) {
        inform("No remote set for this branch, using default remote 'origin'")
      }
      remote <- "origin"
    }
  }

  if(isTRUE(mirror)) {
    refs <- info$reflist
    # Ignore github's special refs
    refs <- refs[!grepl("^refs/pull", refs)]
    refspec <- paste0(refs, ":", refs)
  }
  if(!length(refspec))
    refspec <- info$head
  refspec <- as.character(refspec)
  if(isTRUE(force))
    refspec <- sub("^\\+?","+", refspec)

  host <- remote_to_host(repo, remote)
  key_cb <- make_key_cb(ssh_key, host = host, password = password)
  cred_cb <- make_cred_cb(password = password, verbose = verbose)

  .Call(R_git_remote_push, repo, remote, refspec, key_cb, cred_cb, verbose)
  if(is.null(set_upstream))
    set_upstream <- isTRUE(is.na(info$upstream)) && !isTRUE(info$bare)

  if(isTRUE(set_upstream)){
    git_branch_set_upstream(paste0(remote, "/", info$shorthand), repo = repo)
  }
  git_repo_path(repo)
}

#' @export
#' @rdname git_fetch
#' @useDynLib gert R_git_repository_clone
#' @param url remote url. Typically starts with `https://github.com/` for public
#' repositories, and `https://yourname@github.com/` or `git@github.com/` for
#' private repos. You will be prompted for a password or pat when needed.
#' @param path Directory of the Git repository to create.
#' @param ssh_key path or object containing your ssh private key. By default we
#' look for keys in `ssh-agent` and [credentials::ssh_key_info].
#' @param branch name of branch to check out locally
#' @param password a string or a callback function to get passwords for authentication
#' or password protected ssh keys. Defaults to [askpass][askpass::askpass] which
#' checks `getOption('askpass')`.
#' @param verbose display some progress info while downloading
#' @examples {# Clone a small repository
#' git_dir <- file.path(tempdir(), 'antiword')
#' git_clone('https://github.com/ropensci/antiword', git_dir)
#'
#' # Change into the repo directory
#' olddir <- getwd()
#' setwd(git_dir)
#'
#' # Show some stuff
#' git_log()
#' git_branch_list()
#' git_remote_list()
#'
#' # Add a file
#' write.csv(iris, 'iris.csv')
#' git_add('iris.csv')
#'
#' # Commit the change
#' jerry <- git_signature("Jerry", "jerry@hotmail.com")
#' git_commit('added the iris file', author = jerry)
#'
#' # Now in the log:
#' git_log()
#'
#' # Cleanup
#' setwd(olddir)
#' unlink(git_dir, recursive = TRUE)
#' }
git_clone <- function(url, path = NULL, branch = NULL, password = askpass, ssh_key = NULL,
                      bare = FALSE, mirror = FALSE, verbose = interactive()){
  stopifnot(is.character(url))
  if(!length(path))
    path <- file.path(getwd(), basename(url))
  stopifnot(is.character(path))
  stopifnot(is.null(branch) || is.character(branch))
  verbose <- as.logical(verbose)
  path <- normalizePath(path.expand(path), mustWork = FALSE)
  host <- url_to_host(url)
  key_cb <- make_key_cb(ssh_key, host = host, password = password)
  cred_cb <- make_cred_cb(password = password, verbose = verbose)
  repo <- .Call(R_git_repository_clone, url, path, branch, key_cb, cred_cb, bare, mirror, verbose)
  git_repo_path(repo)
}

#' @export
#' @rdname git_fetch
#' @param rebase if TRUE we try to rebase instead of merge local changes. This
#' is not possible in case of conflicts (you will get an error).
#' @param ... arguments passed to [git_fetch]
git_pull <- function(remote = NULL, rebase = FALSE, ..., repo = '.'){
  repo <- git_open(repo)
  info <- git_info(repo)
  branch <- info$shorthand
  if (branch == "HEAD")
    stop("Repository is currently in a detached head state")

  upstream <- if(length(remote) && nchar(remote)){
    paste0(remote, '/', branch)
  } else {
    info$upstream
  }

  if(!length(upstream) || is.na(upstream) || !nchar(upstream))
    stop("No upstream configured for current branch, please specify a remote")

  if(grepl(".*/pr/\\d+$", upstream)){
    pr <- utils::tail(strsplit(upstream, '/pr/', fixed = TRUE)[[1]], 1)
    try(git_fetch_pull_requests(pr = pr, remote = remote, repo = repo))
  }
  if(git_branch_exists(upstream, local = TRUE, repo = repo)){
    inform("Local upstream, skipping fetch")
  } else {
    git_fetch(remote, ..., repo = repo)
    if(!git_branch_exists(upstream, local = FALSE, repo = repo))
      stop("Failed to fetch upstream branch: ", upstream)
  }
  if(isTRUE(rebase)){
    rebase_df <- git_rebase_list(upstream = upstream, repo = repo)
    if(any(rebase_df$conflicts))
      stop("Found conflicts, rebase not possible. Retry with rebase = FALSE")
    git_rebase_commit(upstream = upstream, repo = repo)
  } else {
    git_merge(upstream, repo = repo)
  }
  git_repo_path(repo)
}
