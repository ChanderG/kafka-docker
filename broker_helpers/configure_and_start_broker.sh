cd $KAFKA_HOME

export BROKER_ID=$(hostname -i | sed 's/\([0-9]*\.\)*\([0-9]*\)/\2/')
sed -i 's/^\(broker\.id=\).*/\1'$BROKER_ID'/' config/server.properties

sed -i 's|^#\(listeners=PLAINTEXT://\)\(:9092\)|\1'`hostname -i`'\2|' config/server.properties

sed -i 's|^\(zookeeper.connect=\)\(localhost\)\(:2181\)|\1zookeeper\3|' config/server.properties

./bin/kafka-server-start.sh config/server.properties
