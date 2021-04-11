## Install
in opt/arm
`git clone -b jessica https://github.com/emmakat/automatic-ripping-machine.git arm`

`chmod +x arm/scripts/docker_build.sh arm/scripts/docker-entrypoint.sh arm/scripts/docker_arm_wrapper.sh`
`chmod +x arm/arm/ripper/main.py`
`chmod -R 777 arm/docs`
`chmod +x arm/scripts/docker_build.sh`

#Build the image:
`arm/scripts/docker_build.sh`


#Now create the container:
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
   -v "/media/arm/storage:/home/arm" \
   -v "/media/arm/storage/Music:/home/arm/Music" \
   -v "/media/arm/storage/config:/home/arm/config" \
   -v "/media/arm/storage/logs:/home/arm/logs" \
   -v "/media/arm/storage/media:/home/arm/media" \
    --cap-add SYS_ADMIN \
    --security-opt apparmor:unconfined \
    --restart "always" \
    --name "arm-rippers" \
    arm-combined:latest
```
#finally!
`sudo chmod -R 777 /media/arm/storage`

Open localhost:8080 and setup the admin account


**The UID and GID must exist outside the container**

for more details please use [the wiki](https://github.com/1337-server/automatic-ripping-machine/wiki/docker)
 
## Troubleshooting
 Please see the [wiki](https://github.com/1337-server/automatic-ripping-machine/wiki/).

## Contributing

Pull requests are welcome.  Please see the [Contributing Guide](https://github.com/1337-server/automatic-ripping-machine/wiki/Contributing-Guide)

If you set ARM up in a different environment (harware/OS/virtual/etc), please consider submitting a howto to the [wiki](https://github.com/1337-server/automatic-ripping-machine/wiki/).

## License

[MIT License](LICENSE)


### This docker is possible thanks to [Deekue's Repo](https://github.com/deekue/automatic-ripping-machine/tree/docker) & [Automatic Ripping Machine](https://github.com/automatic-ripping-machine/automatic-ripping-machine)
