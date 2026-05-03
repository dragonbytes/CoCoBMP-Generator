# CoCo BMP Screenshot Generator

I wrote this BMP generator for one of my other projects, but thought others might find it useful and/or interesting to play with themselves.
I wanted a way to capture a screenshot of a CoCo 3 text-mode screen for sharing with people online that would work on <b>real hardware</b> as well as emulators.
And I wanted it to all be done on the CoCo-side of things, so that all you need to do is copy the file off of your disk to the computer of your choice and voila, 
you can share it online!

<br>
<div align="center">
    <img src="./docs/basic_screenshot0.bmp">
<p><i>WIDTH 80 Screenshot</i></p>
    <img src="./docs/basic_screenshot1.bmp">
<p><i>WIDTH 40 Screenshot</i></p>  
</div>
<br>

At the moment, it only supports 40 and 80 column "Hi-Res" text modes, but in the future i'd like to get the standard 32-column VDG mode working as well.

### Usage

Although this is a Machine Language tool, i've structured it to be as friendly as possible for calling from BASIC. All the relevant variables you might want to set start RIGHT at the routine's LOAD address ($3000 by default), so you can use POKEs to set those based on the offset information found in the code comments. 

The 3 required parameters that you must set are:
- Screen Width (Offset 0)
- Screen Height (Offset 1)
- Destination Drive Number (Offset 10)

There are additional parameters you can optionally change, but by default, it will assume the screen mode you are capturing has attributes enabled and border color value of 0.

## Warning

Although I use BASIC's DSKCON routine for safely reading/writing to disk, for simplicity, I am managing the RS-DOS filesystem parts manually and it could <b>absolutely</b> 
be buggy and should be considered unstable until I can do more testing. <b>Do not save screenshots to important disks unless you have them backed up!</b>
And if you do encounter any disk-related bugs, please reach out to me with a report so that I can address them.
