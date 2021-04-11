## Hello!  
This is a fork of the awesome project https://github.com/1337-server/automatic-ripping-machine/tree/docker 
The readme and some of the files have been *significantly* modified to suit my needs so you should probably not use it as I can't respond to support requests.

### Pre-requisites
1. From a fresh image with Ubuntu 20.10 minimal install  
2. Create the arm user and set a password  
3. Install VSCodium, lsscsi, and any other needed utilities as desired  
4. Setup all of the optical drives so that the arm (non-root) user can mount them. Run `lsscsi -g` to verify their mountpoints if you're unsure.  
  -run `sudo mkdir -p /mnt/dev/sr0` and repeat for each device, e.g., sr1, sr2, etc  
  -edit fstab and add an entry for each drive  
  `sudo nano /etc/fstab`     
  `/dev/sr0  /mnt/dev/sr0  udf,iso9660  users,noauto,exec,utf8  0  0` etc


### Install

From opt/arm (you may need to chmod -R /opt in order to do the git clone without sudo). YMMV - be careful!

`git clone -b jessica https://github.com/emmakat/automatic-ripping-machine.git arm`  

Now fix the permissions  
```
chmod +x arm/scripts/docker_build.sh arm/scripts/docker-entrypoint.sh arm/scripts/docker_arm_wrapper.sh   
chmod +x arm/arm/ripper/main.py  
chmod -R 777 arm/docs  
chmod +x arm/scripts/docker_build.sh
```
**Storage for files**    
This repo assumes that you want to store things somewhere else besides your home directory. 
  You need to edit docker-entrypoint.sh line 11 with the correct path for you:
  `export STORAGE="/path/to/your/storage/"`  
**important!** if you do NOT want to have a separate storage drive, you have to comment the STORAGE variable out or remove it.   
  AND modify line 27 to reference the HOME variable instead of storage!  
  `thisDir="${STORAGE}/${dir}"`


### Build the image:
`arm/scripts/docker_build.sh`

### Setup the udev rules 
`setup/docker-setup.sh`  
(this step is kindof broken right now, but the important thing is to get the docker-arm.rules copied into /etc/udev/rules.d and then force a reload of udevadm control)  
`install setup/docker-arm.rules /etc/udev/rules.d/docker-arm.rules`  
`sudo udevadm control --reload`

### Create the container:
Remember to modify this for YOUR unique configuration!
 ```
docker run -d \
    --device="/dev/sr0:/dev/sr0" \
    --device="/dev/sr1:/dev/sr1" \
    --device="/dev/sr2:/dev/sr2" \
    --device="/dev/sr3:/dev/sr3" \
    --device="/dev/sr4:/dev/sr4" \
    --device="/dev/sr5:/dev/sr5" \
    --device="/dev/sr6:/dev/sr6" \
    -p "8080:8080" \
    -e UID="1000" -e GID="1000" \
   -v "/path/to/your/storage/:/home/arm" \
   -v "/path/to/your/storage/Music/:/home/arm/Music" \
   -v "/path/to/your/storage/config/:/home/arm/config" \
   -v "/path/to/your/storage/logs/:/home/arm/logs" \
   -v "/path/to/your/storage/media/:/home/arm/media" \
    --cap-add SYS_ADMIN \
    --security-opt apparmor:unconfined \
    --restart "always" \
    --name "arm-rippers" \
    arm-combined:latest
```
### Fix the permissions on storage device
`sudo chmod -R 777 /path/to/your/storage/`

### Open localhost:8080 and setup the admin account

See the original project's [wiki](https://github.com/1337-server/automatic-ripping-machine/wiki/docker) for more information
 
## Contributing

Pull requests may be considered if they improve the documentation or something in the code that could be done better, but I strongly urge you to send PR's to the [main project](https://github.com/1337-server/automatic-ripping-machine) instead!

## License

[MIT License](LICENSE)


### This docker is possible thanks to [1337-server's repo](https://github.com/1337-server/automatic-ripping-machine/tree/docker)
