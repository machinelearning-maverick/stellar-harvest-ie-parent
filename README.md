# Project information

StellarHarvest Insight Engine - predicts and visualizes the (earth, space) weather-related vulnerabilities for agriculture. It collects space weather data e.g. planetary K-index, which is used to characterize the magnitude of geomagnetic storms and earth agricultural data e.g. crop calendars for global agricultural production.

StellarHarvest Insight Engine predicts and visualizes earth+space weather threats for agriculture via streaming JSON into Kafka pipelines with modular ingestion, modeling, and persistence.

1. **stellar-harvest-ie-config**

    Shared configuration, central place for magic constants, shared settings, logging decorators, and test fixtures.

    * ```No runtime dependencies on external libraries```

2. **stellar-harvest-ie-models**

    Define data shapes, both validation schema and persistence entities for all data sources using Pydantic.

    * Depends on ```stellar-harvest-ie-config```

3. **stellar-harvest-ie-producers**

    Ingestion module for real-time data sources (e.g., NOAA SWPC) into Kafka.

    * Depends on ```stellar-harvest-ie-config```
    * Depends on ```stellar-harvest-ie-models```

4. **stellar-harvest-ie-stream**

    Thin wrapper around Kafka client factories and stream configuration.

    * Depends on stellar-harvest-ie-producers

5. **stellar-harvest-ie-consumers**

    Kafka-to-Postgres consumer module. Handles streaming data, and preparing it for persisting.
    
    * Depends on ```stellar-harvest-ie-models```
    * Depends on ```stellar-harvest-ie-store```

6. **stellar-harvest-ie-store**

    Persistence layer: database engine, session factory, and schema initialization.

    * Depends on stellar-harvest-ie-config
    * Depends on stellar-harvest-ie-models

7. **stellar-harvest-ie-ui**

    FastAPI-based UI/dashboard service, real-time and REST API.

8. **stellar-harvest-ie-ml-stellar**

    Machine learning pipelines for training and serving predictive models on stellar (space weather) data.

9. **stellar-harvest-ie-deployment**

    Infrastructure orchestration: ZK, Kafka, Postgres, migrations, bootstrap scripts. Holds Docker-Compose/K8s manifests and infra bootstrapping.