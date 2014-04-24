#!/bin/sh
#
# ~/.xinitrc
#
# Executed by startx (run your window manager from here)

if [ -d /etc/X11/xinit/xinitrc.d ]; then
  for f in /etc/X11/xinit/xinitrc.d/*; do
    [ -x "$f" ] && . "$f"
  done
  unset f
fi


eval $(ssh-agent -s) 
xkbcomp -I/home/luke/xkb /home/luke/xkb/keymap/macbook78 $DISPLAY 
xset r rate 200 45
#xset s on 
#xset s blank 
#xset s 600 600 
xset dpms 300 420 600
#xrandr --output eDP1 --mode 1600x1200 
syndaemon -k -K -d -i 0.2 -R &

ibus-daemon -d  &

exec i3

#exec xterm
#exec wmii
#exec xmonad


#exec gnome-session
# exec startkde
# exec startxfce4
# ...or the Window Manager of your choice
