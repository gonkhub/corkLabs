# Sounds to audition

Drop `.wav`, `.ogg` or `.mp3` files here (let the editor import them), then in
the game's Terminal:

    sound                      list them (plus the built-in tone, noise, hum, click)
    sound play <name> 15       15 m in front of the camera you're listening through
    sound play <name> tinker   on a robot (it rides along)
    sound loop <name> hall     looping in the middle of a room
    sound stop                 stop everything auditioned

You hear them through the Cameras app: the open camera in single view, the
feed under the mouse in the grid. They go to the World bus (see the Audio tab
in the editor), under the camera Feed bus.
