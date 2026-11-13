# Called by digest-updates.sh with the PR diff as $diff; see that script.

# refs lists the image references on the added and removed lines of the diff:
# the sign of the line, the index of its file in the diff, the repository path
# without the registry host, the tag, and the digest, which is null when the
# reference has none. The --- and +++ header lines are read as well, but git
# prefixes their paths with a/ and b/, so they could match only an image
# named under a/ or b/.
def refs:
  [foreach ($diff | split("\n")[]) as $line ({file: 0, out: []};
    if ($line | startswith("diff --git ")) then
      {file: (.file + 1), out: []}
    elif ($line | test("^[-+]")) then
      .file as $file
      | .out = [$line | .[0:1] as $sign
          | capture("(?<ref>[A-Za-z0-9][A-Za-z0-9._/:-]*):(?<tag>[A-Za-z0-9_][A-Za-z0-9._-]*)(?:@sha256:(?<digest>[0-9a-f]{64}))?"; "g")
          | {sign: $sign, file: $file, tag, digest,
             repo: (.ref | split("/")
               | if length > 1 and (.[0] | test("[.:]"))
                 then .[1:] else . end
               | join("/"))}]
    else
      .out = []
    end;
    .out[])];

def short_digest:
  if type == "string" then ltrimstr("`") | rtrimstr("`") else "" end;

refs as $refs
| map(
    (.prevVersion | short_digest) as $prev
    | if .packageEcosystem == "docker" and ($prev | test("^[0-9a-f]{7,64}$")) then
        .dependencyName as $name
        | [$refs[] | select(.repo == $name)] as $mine
        | [$mine[] | select(.sign == "-")] as $removed
        | [$mine[] | select(.sign == "+")] as $added
        | if all($mine[]; .digest != null)
            and any($removed[]; .digest | startswith($prev))
            and ($removed | map([.file, .tag]) | sort) == ($added | map([.file, .tag]) | sort)
          then .updateType = "version-update:digest"
          else . end
      else . end)
