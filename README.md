# repostory
CLI PPA/deb archive distribution checker for end users.

repostory is an old script I found on ubuntuforums.org, by the user [Framli](https://ubuntuforums.org/member.php?u=750404). His original script is in the repository here as `repostory`.

I used his script happily for a long while, until [zenity](https://linux.die.net/man/1/zenity) changed their interfaces, and his script no longer worked. So I updated it. That's a few years ago, and the results are in `repo`.
At this point I also removed zenity completely, so it would be easier to use the script over ssh.

Then, a year ago or so, I came across [luash](https://github.com/zserge/luash) and I immediately wanted to start converting my existing lua shell scripts to using it - but I had to get my feet wet first, so I made `r.lua`.

All the scripts are terrible, but they get the job done. Pull requests welcome!

folk@folk.wtf
