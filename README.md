RapidPro Message Mage
=====================

High performance [Dropwizard](https://dropwizard.github.io/dropwizard) based webserver for receiving incoming messages on behalf of [RapidPro](https://github.com/rapidpro/rapidpro).

Building
--------
Currently one of the dependencies doesn't exist in Maven Central so must be built locally:

    git clone git@github.com:tradier/dropwizard-raven.git
    cd dropwizard-raven
    git checkout fc2d93f7710d4e32ca727110d3eb3093b15b4de6
    mvn clean install

Without tests:

    mvn clean package -DskipTests=true

Building with tests requires that Postgresql and Redis servers are running, then:

    testdb/init.sh temba  # setup the test database based on schema from given database
    mvn clean package     # run the build with tests against the test database

Running
-------
The Mage configuration file contains several references to environment variables which must be defined on your system.
This can be done easily in a wrapper shell script which sets the variables, e.g.

    #!/bin/bash
    export PRODUCTION=0
    export DATABASE_URL=...
    export REDIS_HOST=localhost
    export REDIS_DATABASE=8
    export TEMBA_HOST=localhost:8000
    export TEMBA_AUTH_TOKEN=...
    export TWITTER_API_KEY=...
    export TWITTER_API_SECRET=...
    export SEGMENTIO_WRITE_KEY=
    export SENTRY_DSN=
    export LIBRATO_EMAIL=
    export LIBRATO_API_TOKEN=
    exec "$@"

And then is invoked like:

    ./env.sh java -jar `ls target/mage-*.jar` server config.yml

Debugging
---------
In IntelliJ:

1. Add new run configuration of type _Application_
2. Set main class to _io.rapidpro.mage.MageApplication_
3. Set program arguments to _server config.yml_ 
