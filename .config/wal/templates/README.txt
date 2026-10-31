REMEMBER TO SYMLINK DUNSTRC TO SYNC THE NOTIFICATION COLOURS WITH THE WALLPAPER:

# 1. Delete the old dunstrc file (if it exists)
rm ~/.config/dunst/dunstrc

# 2. Create a symlink pointing to the Pywal-generated file
ln -s ~/.cache/wal/dunstrc ~/.config/dunst/dunstrc


AND GTK TOO:

rm ~/.config/gtk-3.0/gtk.css
ln -sf ~/.cache/wal/gtk.css ~/.config/gtk-3.0/gtk.css

Verify:

ls -la ~/.config/gtk-3.0/gtk.css


More tips:

plasma apps use plasma-integration for theming
