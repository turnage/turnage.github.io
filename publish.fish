#!/usr/bin/fish

cd ..
rm -rf paytonturnage.com
cp -R turnage.github.io paytonturnage.com
cd paytonturnage.com
rm -rf .git
zola build
cd public
git init
git add .
git commit -m "deploy"
git push --force git@github.com:turnage/turnage.github.io.git master:gh-pages
