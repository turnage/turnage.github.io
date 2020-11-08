#!/usr/bin/fish

set articles (git ls-files | grep -e \.md)
for article in $articles
  set name (echo $article | sed -e s/.md//g)
  cat $article | podiat > $name.md.new
  mv $name.md.new $name.md
end
