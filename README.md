# Sourcemod Plugins

This repository contains the plugins that I either made or modified.  
  
The reason for modifying a plugin can range from fixing a bug, fixing an exploit or making it 
compatible with a new plugin.

---
### L4D2 Server Restarter
---

Restarts the server automatically after every game. The restart conditions are:

- There are no human players left in the server.
- A map change / load has happened at some point.

L4D2 competitive servers seem to be unable to stay running for a while before crashing. Restarting
after every game prevents crashes and performance loss.

Make sure the plugin is loaded in all the configs as well as vanilla.

##### Required files
> - l4d2_server_restarter.smx (main plugin)

---
### L4D Rock Lag Compensation
---

Offers lag compensation for tank rocks.   
  
[Checkout my post on AlliedModders](https://forums.alliedmods.net/showthread.php?t=315345) for more information.

##### Required files

> - l4d_rock_lagcomp.smx (main plugin)
> - rock_lagcomp.txt (gamedata for windows & l4d1 compatibility, necessary even for l4d2)

---
### Mix Manager
---

Offers a !mix (and !stopmix) command that allows people to seamlessly pick captains and teams through menus during readyup.

##### Required files

> - l4d2_mix.smx (main plugin)
> - readyup.smx (modified to stop showing the ready pannel when the mix manager is active)

---
### L4D2 Health Temp Bonus
---

L4D2 competitive health bonus scoring system.

[Checkout the top comments in the source](https://github.com/LuckyServ/sourcemod-plugins/blob/master/source/l4d2_health_temp_bonus.sp) for more information.

##### Required files

> - l4d2_health_temp_bonus.smx (main plugin)

---
### Admin Cheats
---

Provides ability to use cheat commands for admins.

##### Required files

> - admincheats.smx (main plugin, modified to work well with competitive L4D2 servers)



