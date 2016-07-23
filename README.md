# kafka cluster on docker

This setup is to run a Kafka cluster on Docker.

## Images required

* wurstmeister/zookeeper
* wurstmeister/kafka

wurstmeister's kafka-docker has some problems:

* It needs the Docker client included in the Alpine Linux's package manager to match the Docker server you are running. This is because some Docker commands on the host are being run from inside the container.
* It tries to map the different Kafka broker containers to the host on different ports. This means in effect you are using the different brokers on a single IP. A more authentic experience would be to have them on seperate IPs inside the bridge network started by Docker.

An alternative, more hands on approach.

## Basic plan

We run one Zookeeper container.

For each Kafka broker, we customize the below config required by a Kafka server and start a container. These containers will be our Kafka cluster.

Now for submitting to the log, we need a Producer. We start up a wurstmeister/kafka container that contains the required scripts and run the producer script. We will simillarly have a container for the consumer.

First, we manually do this. Then we will try to create docker-compose setup for the same.

## Config required for a broker

* broker.id -- unique for each broker
* listeners -- IP of Docker container assigned in the bridge network/compose network
* zookeeper.connect -- the Docker bridge network/ compose network IP of the Zookeeper container

## Manual Run

As hinted at in the Basic Plan section, here is the simplest setup (with just one Kafka broker) done manually.

For this run, we are going to use the default bridge network (that is, do nothing special). Also, the steps below are done when no other containers are running in the host; your IPs will be different, if so. This IP specific business can hopefully be avoided in the compose setup.

This approach is, by design, as manual as possible.

### Zookeeper

First, we start the Zookeeper container. This contains the Zookeeper server binary we need to run.
```
docker run -it --rm wurstmeister/zookeeper /bin/bash
```

Now check the IP from within the container, using `hostname -I`. In my setup, it is `172.17.0.2` which should be the same in your case.

Now we start the Zookeeper server.
```
./bin/zkServer.sh start-foreground
```

### One Kafka Broker

For now, we run only one Kafka broker.

Start the container:
```
docker run -it --rm wurstmeister/kafka /bin/bash
```

Check the IP. It should be `172.17.0.3`.

The directory of interest is `$KAFKA_HOME`.
```
cd $KAFKA_HOME
```

You now need to edit the required options in `config/server.properties`. Set the following values:

* broker.id -- leave it to 0; we have only 1 broker
* listeners -- PLAINTEXT://172.17.0.3:9092, the IP of this broker
* zookeeper.connect -- 172.17.0.2:2181, the IP to reach the Zookeeper instance

We can now start the server:
```
./bin/kafka-server-start.sh config/server.properties
```

### One Producer

We are going to start a single producer.

We need to start a `wurstmeister/kafka` container as only that has the required scripts.
So, as before:
```
docker run -it --rm wurstmeister/kafka /bin/bash
$ cd $KAFKA_HOME
```

We can now start a producer. Before that let us take stock of existing topics.

To get a list of existing topics:
```
$KAFKA_HOME/bin/kafka-topics.sh --list --zookeeper 172.17.0.2
```
It should come up empty, obviously.

Let us create a topic, `my_topic`:
```
$KAFKA_HOME/bin/kafka-topics.sh --create --topic my_topic --partition 1 --replication-factor 1 --zookeeper 172.17.0.2
```

Finally the producer:
```
$KAFKA_HOME/bin/kafka-console-producer.sh --broker-list 172.17.0.3:9092 --topic my_topic
```

You can enter stuff into the command line now. Each line is considered a seperate message.

### One Consumer

Just like the producer case, we need to start the container:
```
docker run -it --rm wurstmeister/kafka /bin/bash
$ cd $KAFKA_HOME
```

Consume from the beginning:
```
$KAFKA_HOME/bin/kafka-console-consumer.sh --zookeeper 172.17.0.2:2181 --topic my_topic --from-beginning
```

You should be able to see the messages from the producer.

## Automation using Compose

Now, we would like to automate as much as possible of the above steps. We would like to be able to scale the number of brokers seamlessly as well.

Setting up a compose file for a single broker (like the above case) is a very easy task. We can just convert the manual steps into a compose file. What would be better is a compose setup which permit adding more brokers using the `docker-compose scale` command.

For the system to be simple, it is best if we can configure the Kafka broker params at container start time. That is, I would prefer not to build a seperate image for each Kafka broker and would like to use the same image (`wurstmeister/kafka`) and configure it at start time.

So, I opt to have the required configuration as bash commands to be run before we start the Kafka server. Specifcally, we need to ensure correct values for each of the config values in the config file. We shall do that by using the commands available from bash, namely `sed`, `hostname`, etc.

So, for each config, below is our value setup:

### broker.id
Needs to be an unique integer.

Note that the brokers (containers) are going to be started on a seperate network. Each container can obviously access it's own IP. So the last (least significant) 8 bits of the IP (for simplicity) would be unique to each broker (assuming reasonable IP allocation and limited number of brokers).

```
export BROKER_ID=$(hostname -i | sed 's/\([0-9]*\.\)*\([0-9]*\)/\2/')
sed -i 's/^\(broker\.id=\).*/\1'$BROKER_ID'/' config/server.properties
```

If required, we can use more number of bits to set the broker id. But for our cases, 251 brokers should be more than what you need on a single host.

### listeners
Needs to be the container's IP. Straight-forward substitution.

```
sed -i 's|^#\(listeners=PLAINTEXT://\)\(:9092\)|\1'`hostname -i`'\2|' config/server.properties
```

### zookeeper.connect
Zookeeper IP connection. We link the Kafka broker containers to the zookeeper container, meaning the hostname zookeeper directly resolves to the correct IP.

```
sed -i 's|^\(zookeeper.connect=\)\(localhost\)\(:2181\)|\1zookeeper\3|' config/server.properties
```

* * *

Now that we have the techniques, my first idea was to unceremoniously shove them into the docker-compose file. Then, the docker-compose file would be the single source of truth. However, it seems as though a `bash -c` command does not have access to the ENV variables inside the container.

So, we are taking a cleaner approach, though still not the most modular method, of putting these into a script, mounting the folder with the script onto the Kafka image containers and running the script before starting the server.
