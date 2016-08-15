cd $KAFKA_HOME

export BROKER_ID=$(hostname -i | sed 's/\([0-9]*\.\)*\([0-9]*\)/\2/')
sed -i 's/^\(broker\.id=\).*/\1'$BROKER_ID'/' config/server.properties

sed -i 's|^#\(listeners=PLAINTEXT://\)\(:9092\)|\1'`hostname -i`'\2|' config/server.properties

sed -i 's|^\(zookeeper.connect=\)\(localhost\)\(:2181\)|\1zookeeper\3|' config/server.properties

# export environment variables used in create-topics.sh
export KAFKA_ZOOKEEPER_CONNECT=zookeeper
export KAFKA_PORT=9092

/usr/bin/create-topics.sh & ./bin/kafka-server-start.sh config/server.properties
