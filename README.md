🛡️ ConfluxDB IaC Blauwdruk

    Het bouwen van een Veilige, Schaalbare en Geautomatiseerde Cloudinfrastructuur met Terraform voor het ConfluxDB Dataplatform.

Inhoudsopgave

    De Fundamentele Pijlers

    De Zero-Trust Netwerkperimeter

    De Veilige Data- & Applicatiekern

    De Tijdelijke & Veilige Automatisatiemotor

    Geïntegreerde Beveiliging & Governance

De Fundamentele Pijlers

    Onze architectuur is gebouwd op ononderhandelbare principes die vanaf dag één een robuuste, veilige en onderhoudbare productieomgeving garanderen.

🛡️ Veiligheid door Ontwerp
	

📜 Infrastructuur als Code
	

🤖 Operationele Automatisering
	

💰 Kostenbewustzijn

Een zero-trust model met het 'principle of least privilege' verweven in elk component, van netwerk tot IAM.
	

Eén enkele bron van waarheid in Terraform voor reproduceerbare, auditeerbare en versie-gecontroleerde infrastructuur.
	

Alles automatiseren, van CI/CD-pipelines tot resourceplanning, om menselijke fouten en operationele frictie te minimaliseren.
	

Gebruikmaken van serverless compute en geautomatiseerde schaling om infrastructuurkosten direct af te stemmen op platformgebruik.
De Zero-Trust Netwerkperimeter

    Onze VPC is een fort zonder publieke toegangspunten voor kritieke resources. Alle communicatie wordt expliciet gecontroleerd, wat volledige isolatie van het openbare internet garandeert.

Alle kritieke componenten zoals de RDS-database, het Fargate-dataplatform en de GitHub Runners bevinden zich in een privé-subnet. Ze hebben geen direct inkomend internetverkeer. Voor uitgaand verkeer (bijv. voor het downloaden van packages) wordt een NAT Gateway in een publiek subnet gebruikt. Communicatie met AWS-diensten zoals S3 en ECR verloopt veilig binnen het AWS-netwerk via VPC Endpoints.
De Veilige Data- & Applicatiekern

    Onze data en applicaties draaien op serverless Fargate, erven sterke isolatie en worden beheerd door fijnmazige IAM-rollen die het 'principle of least privilege' afdwingen.

Private & Veerkrachtige RDS Database

    ✅ 100% Plaatsing in Privé Subnet: De database is niet bereikbaar vanaf het internet.

    ✅ Versleuteld 'at Rest' & 'in-Transit': Data is altijd versleuteld.

    ✅ Multi-AZ: Hoge beschikbaarheid en automatische failover.

Scheiding van Fargate IAM-Rollen

    We gebruiken twee afzonderlijke rollen voor elke service: één voor de ECS-agent om de container te starten, en één voor de applicatiecode zelf. Deze scheiding is cruciaal voor 'least privilege' toegang.

De Taakuitvoeringsrol heeft minimale permissies (ECR images pullen, logs sturen), terwijl de Taakrol specifieke permissies heeft die de applicatie nodig heeft (toegang tot de database, secrets, etc.).
De Tijdelijke & Veilige Automatisatiemotor

    CI/CD wordt geactiveerd via een veilige, ontkoppelde webhook-architectuur. Elke taak draait in een schone, eenmalig te gebruiken Fargate-container, die authenticeert met kortlevende tokens via OIDC, waardoor statische credentials worden geëlimineerd.

Het proces is volledig geautomatiseerd en ontkoppeld om de veiligheid en betrouwbaarheid te maximaliseren.

GitHub Webhook (op merge naar main) ➔ API Gateway (valideert verzoek) ➔ SQS Wachtrij (garandeert aflevering) ➔ Lambda Functie (start de runner) ➔ Tijdelijke Fargate Runner (voert CI/CD-taak uit en stopt).
Geïntegreerde Beveiliging & Governance

    Beveiliging is geen feature, het is de fundering. We gebruiken identiteitsgebaseerde netwerkregels en een gecentraliseerde strategie voor het beheer van secrets die hardgecodeerde credentials volledig elimineert.

Securitygroepen als Identiteit

    In plaats van breekbare IP-regels, definiëren we toegang op basis van de ID van de bron-securitygroep. Dit creëert dynamisch, veerkrachtig netwerkbeleid.

┌─────────────────┐      ┌──────────────────────────────────────────┐      ┌─────────────────┐
│                 │      │ Staat Inkomend Verkeer toe op Poort 5432 │      │                 │
│    App SG       │─────▶│                                          │─────▶│      DB SG      │
│ (Fargate Service) │      │           VAN: App SG ID               │      │ (RDS Instantie) │
│                 │      └──────────────────────────────────────────┘      │                 │
└─────────────────┘                                                        └─────────────────┘

Veilig Beheer van Secrets

    Secrets worden nooit in code opgeslagen. Ze worden veilig opgehaald tijdens runtime door de ECS-agent en direct als omgevingsvariabelen in de container geïnjecteerd, waardoor blootstelling wordt geminimaliseerd.

Deze methode van Runtime Injectie is de standaard en meest veilige aanpak voor ~95% van alle gebruiksscenario's.

© 2025 ConfluxDB. Een veilige, schaalbare en geautomatiseerde infrastructuur.