```                                                              
                                                           ░░░░░░░░           
      ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░█████░░░░░       
     ░░██████████████████████████████████████████████████████▒▒██████░░░     
     ░████▒▒▒▒▒   █▒▒▒▒▒▒▒   █▒▒▒▒▒   ██▒▒▒▒▒   ██▒▒▒▒▒▒   ███▒█▒▒   ███░░░   
     ░███▒▒▒▒▒▒▒▒██▒▒▒▒▒▒▒▒▒▒█▒▒▒▒██▒▒▒█▒▒▒▒▒▒▒▒▒██▒▒▒▒▒██▒▒▒███▒▒▒▒▒▒███░░  
     ░████▒▒▒▒███████▒▒▒▒▒████▒▒▒▒▒█▒▒▒█▒▒▒▒██▒▒▒▒██▒▒▒▒▒█▒▒▒███▒▒▒▒▒▒▒▒██░░ 
     ░░██▓▓░░░░░░░░░██░░░░░██░░░░░░░░░██░░░░░█░░░░░█░░░░░░░░████░░░░██░░░██░ 
      ░░▓███████░░░░░█░░░░░██░░░░░░████░░░░░░░░░░░░░█░░░████████░░░░░█░░░░█░░
       ░███░   █░░░░░██░░░░░█░░░░░░░░░██░░░░░█░░░░░░█░░░ ███████░░░░░█░░░░██░
       ░███░░░░░░░░░░░█░░░░░█░░░░░█░░░░█░░░░░█░░░░░██░░░░░██████░░░░░█░░░░░█░
       ░█▓▓▒▒▒▒▒▒▒▒▒▒██▒▒▒▒▒█▒▒▒▒▒█▒▒▒▒█▒▒▒▒▒█▒▒▒▒▒█▒▒▒▒▒▒▒█████▒▒▒▒▒▒▒▒▒▒██░
       ░▓███▒▒▒▒▒▒▒▒███▒▒▒▒██▒▒▒▒██▒▒▒██▒▒▒▒██▒▒▒▒██▒▒▒▒▒▒███████▒▒▒▒▒▒▒▒██░░
       ░░███████▓███████████████████▓████████████▓████████████████▓███████░░ 
        ░░█████▓███████████████████▓████████████▓████████████████▓███████░░  
         ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   
```
# strapd

A multi-distro quick-bootstrap for comfort and efficiency.

# Why would I use this?

For right now, you shouldn't, unless you explicitly wanna help test; 
That's quickly changing but I'd like to be up front: we're still getting 
set up. Lots of cleanup to do, lots of configurations to try. That said...

It's nice when a lot of people use the same powerful tool, configured in 
approximately the same way. Setting up a linux box is a journey, and one
worth taking! But once you've done a few, automating and homogenizing a 
bunch of the process is useful.

## Install

#### Fresh 
build the image with `sudo iso/build.sh` and write it to a stick. [iso/README.md](iso/README.md) 
covers building and flashing. On the box, run `strapd-install`.

#### On your existing Arch box

```sh
git clone <this repo> ~/strapd
cd ~/strapd && ./install.sh
```

## Tests

```sh
bash test/shell          # run whenever
bash test/acceptance     # needs a live session
```

The shell tests are approximately unit tests, acceptance spins up virtualized systems

## Questions no one actually asked

##### Is this just a woke fork of Oma-

[That's not a hair question, I'm sorry.](https://youtu.be/X2fGzmphx4U?si=Lx82HZ-ineajc5gG&t=65)

##### Why this workflow?

It's an easy place to onboard linux users fleeing another popular bootstrap.
Convergent evolution is good here, so that we may more easily support one another.
This workflow will also be honed further, we're still pre-0.1.

##### What are your credentials here?

I've just been using linux a long time, and working in ops for a decent while.
"Please package linux to be usable for others" is extremely my wheelhouse

##### What's next?

An approximate roadmap:

- Get the existing experience tested and refined
  - We want to ensure solid support on x86 Apple, Lenovo, and *Framework
    machines, and then expand into arm where possible within those ecosystems
  - We want at least one active user for each of Arch, Nixos, and Debian,
    and, at leas one active user for each of Sway, Mango, and Niri
  - We want automated iso builds and super easy installs.
  - We want the code to feel good to work with. There's a fair bit of cleanup
    to do, and some fingerprints to file off.

- Modularize
  - Omakase is an approach, but this is more kaiten-zushi; we're all eating fish
    and rice, but, you might prefer a bit of spice, or to try a bit of everything
    As such, a few optional modules will be iterated upon, to expand our potential
    audience, and offer a few new experiences, while keeping a shared Way of Doing
    Things, so that we can easily support one another.

- Advertise
  - This is a product of a Moment, we need to raise awareness somewhat quickly

*Questions about Framework are also not hair questions.

This repo will aspire to 1.0, which will honor the basic behavrioural contract 
of that other bootstrap's version 4, and serve as "base" for the strapd ecosystem.

##### Is this just slop?

It's "agentically engineered software"; I am using llms. I don't think that matters
but, some of you may, and lying about it is gross. I'm also writing chunks by hand,
and accepting contributions, without any explicit AI policy.

##### Who did that ascii art?

Me, Jae. I used [ascii draw studio](https://www.asciiart.eu/ascii-draw-studio/app)
It was important to me that any iconography for this project have a known, consenting,
not-generated origin, so, I'm doing it for now.
