# Digest

RSS/Atom feed aggregator that generates markdown digests.

## Reading

Each configured digest produces a `{name}.md` file in the repository root. These files are overwritten when new items are found.

To get the latest digest, pull the repo or browse to `{name}.md` on GitHub. Daily tags (`v{YYYY-MM-DD}`) mark each update.

### Terminal Browsing 

Use `git show` with the desired tag and digest file:

```shell
$ git show v2026-01-15:ruby.md
```

Using `git` and `fzf`, you can browse digests by tag via a preview window:

```shell
$ git tag --sort=-creatordate | fzf --preview 'git show {}:<DIGEST_FILE>.md' --preview-window=top:80%:wrap
```

For markdown rendering, I recommend [`glow`](https://github.com/charmbracelet/glow):

```shell
$ git tag --sort=-creatordate | fzf --preview 'git show {}:<DIGEST_FILE>.md | glow -w0' --preview-window=top:80%:wrap
```

The included `./digest` executable uses [`bat`](https://github.com/sharkdp/bat) for syntax highlighting, rather than rendering.

## Generating

```
ruby digest.rb
```

Fetches all configured feeds concurrently and writes digests for any with new items since `.last_run`.

To re-fetch the last 24 hours:

```
rm .last_run && ruby digest.rb
```

## Configuration

Feed URLs are grouped under named digests in `config.yml`:

```yaml
digests:
  ruby:
    - https://rubyweekly.com/rss
    - https://railsatscale.com/feed.xml
  python:
    - https://realpython.com/atom.xml
```

Each key creates a `{name}.md` file.

## Files

```
config.yml    Named digest configurations
digest.rb     Main script
.last_run     ISO 8601 timestamp of last run
{name}.md     Generated digests
```

## GitHub Action

Runs daily at 8 AM UTC via `.github/workflows/digest.yml`. Can be triggered manually from Actions > Generate Daily Digest > Run workflow.

Commits `*.md` and `.last_run`, then creates a `v{YYYY-MM-DD}` tag.
