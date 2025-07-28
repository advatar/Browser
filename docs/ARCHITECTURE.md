# Architecture Guide

## Overview

The Decentralized Web Browser is built as a modular, peer-to-peer system that eliminates reliance on centralized infrastructure. This document provides a comprehensive overview of the system architecture, design decisions, and component interactions.

## Table of Contents

- [System Architecture](#system-architecture)
- [Core Components](#core-components)
- [Data Flow](#data-flow)
- [Network Architecture](#network-architecture)
- [Security Model](#security-model)
- [Storage Architecture](#storage-architecture)
- [Component Interactions](#component-interactions)

## System Architecture

### High-Level Overview

```mermaid
graph TB
    subgraph "User Interface Layer"
        UI[Browser UI]
        Tabs[Tab Management]
        AddressBar[Address Bar]
        WalletUI[Wallet Interface]
    end
    
    subgraph "Application Layer"
        Router[Content Router]
        Renderer[Web Renderer]
        WalletCore[Wallet Core]
        Extensions[Extension System]
    end
    
    subgraph "Service Layer"
        P2P[P2P Network Service]
        IPFS[IPFS Service]
        Blockchain[Blockchain Service]
        Storage[Local Storage]
    end
    
    subgraph "Network Layer"
        libp2p[libp2p Stack]
        DHT[Kademlia DHT]
        Bitswap[Bitswap Protocol]
        Gossipsub[Gossipsub]
    end
    
    subgraph "Blockchain Clients"
        Substrate[Substrate Client]
        Ethereum[Ethereum Light Client]
        Bitcoin[Bitcoin Light Client]
    end
    
    UI --> Router
    Tabs --> Renderer
    AddressBar --> Router
    WalletUI --> WalletCore
    
    Router --> P2P
    Router --> IPFS
    Renderer --> Extensions
    WalletCore --> Blockchain
    
    P2P --> libp2p
    IPFS --> Bitswap
    Blockchain --> Substrate
    Blockchain --> Ethereum
    Blockchain --> Bitcoin
    
    libp2p --> DHT
    libp2p --> Gossipsub
    Storage --> IPFS
```

### Component Hierarchy

```mermaid
classDiagram
    class BrowserApp {
        +start()
        +shutdown()
        +handle_events()
    }
    
    class UIManager {
        +create_window()
        +manage_tabs()
        +handle_user_input()
    }
    
    class ContentRouter {
        +route_request(url)
        +resolve_content()
        +cache_content()
    }
    
    class P2PService {
        +initialize_network()
        +discover_peers()
        +handle_messages()
    }
    
    class IPFSService {
        +get_content(cid)
        +pin_content(cid)
        +publish_content()
    }
    
    class BlockchainService {
        +connect_client()
        +sync_headers()
        +submit_transaction()
    }
    
    class WalletService {
        +create_wallet()
        +sign_transaction()
        +manage_keys()
    }
    
    BrowserApp --> UIManager
    BrowserApp --> ContentRouter
    BrowserApp --> P2PService
    
    ContentRouter --> IPFSService
    ContentRouter --> BlockchainService
    
    P2PService --> IPFSService
    BlockchainService --> WalletService
```

## Core Components

### 1. P2P Networking Layer

The P2P networking layer is built on libp2p and provides the foundation for all decentralized communication.

```mermaid
graph LR
    subgraph "libp2p Stack"
        Transport[Transport Layer]
        Muxing[Stream Multiplexing]
        Security[Security Layer]
        Discovery[Peer Discovery]
    end
    
    subgraph "Protocols"
        Kademlia[Kademlia DHT]
        Bitswap[Bitswap]
        Gossipsub[Gossipsub]
        Identify[Identify]
    end
    
    subgraph "Network Transports"
        TCP[TCP]
        QUIC[QUIC]
        WebSocket[WebSocket]
    end
    
    Transport --> TCP
    Transport --> QUIC
    Transport --> WebSocket
    
    Muxing --> Yamux[Yamux]
    Security --> Noise[Noise Protocol]
    
    Discovery --> mDNS[mDNS]
    Discovery --> Bootstrap[Bootstrap Nodes]
    
    Kademlia --> Discovery
    Bitswap --> Muxing
    Gossipsub --> Security
```

#### Key Features:
- **Multi-transport support**: TCP, QUIC, WebSocket
- **Security**: Noise protocol for encryption
- **Multiplexing**: Yamux for stream management
- **Discovery**: mDNS and bootstrap nodes

### 2. IPFS Integration

```mermaid
sequenceDiagram
    participant User
    participant Browser
    participant IPFS
    participant DHT
    participant Peers
    
    User->>Browser: Request ipfs://QmHash
    Browser->>IPFS: Resolve content
    IPFS->>DHT: Find providers
    DHT-->>IPFS: Provider list
    IPFS->>Peers: Request blocks
    Peers-->>IPFS: Content blocks
    IPFS->>Browser: Assembled content
    Browser->>User: Display content
```

#### IPFS Service Architecture:

```mermaid
classDiagram
    class IPFSNode {
        +bitswap: Bitswap
        +blockstore: BlockStore
        +dag: DAGService
        +pin_manager: PinManager
        
        +get(cid: CID) Content
        +put(data: bytes) CID
        +pin(cid: CID)
        +unpin(cid: CID)
    }
    
    class Bitswap {
        +want_list: WantList
        +ledger: Ledger
        
        +want_block(cid: CID)
        +provide_block(block: Block)
        +handle_message(msg: Message)
    }
    
    class BlockStore {
        +get(cid: CID) Block
        +put(block: Block)
        +has(cid: CID) bool
        +delete(cid: CID)
    }
    
    class PinManager {
        +pin_set: HashSet
        
        +pin(cid: CID, recursive: bool)
        +unpin(cid: CID)
        +is_pinned(cid: CID) bool
    }
    
    IPFSNode --> Bitswap
    IPFSNode --> BlockStore
    IPFSNode --> PinManager
    Bitswap --> BlockStore
```

### 3. Blockchain Integration

The blockchain layer supports multiple chains through a unified interface:

```mermaid
graph TD
    subgraph "Blockchain Service"
        ClientManager[Client Manager]
        TxPool[Transaction Pool]
        StateSync[State Synchronization]
    end
    
    subgraph "Light Clients"
        SubstrateClient[Substrate Client]
        EthereumClient[Ethereum Client]
        BitcoinClient[Bitcoin Client]
    end
    
    subgraph "Wallet Integration"
        KeyManager[Key Manager]
        Signer[Transaction Signer]
        HWWallet[Hardware Wallet]
    end
    
    ClientManager --> SubstrateClient
    ClientManager --> EthereumClient
    ClientManager --> BitcoinClient
    
    TxPool --> Signer
    StateSync --> SubstrateClient
    StateSync --> EthereumClient
    
    Signer --> KeyManager
    Signer --> HWWallet
```

#### Substrate Client Architecture:

```mermaid
classDiagram
    class SubstrateClient {
        +config: SubstrateConfig
        +client: Client
        +runtime: Runtime
        
        +connect() Result
        +get_block(hash: Hash) Block
        +submit_extrinsic(ext: Extrinsic) Hash
        +subscribe_events() EventStream
    }
    
    class Transaction {
        +from: AccountId
        +to: AccountId
        +amount: Balance
        +nonce: u32
        +signature: Option~Signature~
        
        +sign(keypair: KeyPair)
        +verify() bool
        +encode() Vec~u8~
    }
    
    class Wallet {
        +keys: HashMap~String, KeyPair~
        +default_key: Option~String~
        
        +create_key(name: String) KeyPair
        +sign_transaction(tx: Transaction) Signature
        +get_address(name: String) AccountId
    }
    
    class KeyPair {
        +key_type: KeyType
        +public_key: PublicKey
        +private_key: PrivateKey
        
        +from_seed(seed: [u8]) KeyPair
        +sign(message: [u8]) Signature
        +verify(message: [u8], sig: Signature) bool
    }
    
    SubstrateClient --> Transaction
    Wallet --> KeyPair
    Transaction --> KeyPair
```

## Data Flow

### Content Resolution Flow

```mermaid
flowchart TD
    Start([User enters URL]) --> Parse{Parse URL scheme}
    
    Parse -->|ipfs://| IPFS[IPFS Resolution]
    Parse -->|ipns://| IPNS[IPNS Resolution]
    Parse -->|ens://| ENS[ENS Resolution]
    Parse -->|http://| Bridge[Bridge Plugin]
    
    IPFS --> Cache{Check Cache}
    IPNS --> ResolveName[Resolve IPNS Name]
    ENS --> QueryENS[Query ENS Contract]
    
    Cache -->|Hit| Display[Display Content]
    Cache -->|Miss| FetchIPFS[Fetch from IPFS]
    
    ResolveName --> FetchIPFS
    QueryENS --> FetchIPFS
    
    FetchIPFS --> DHT[Query DHT for Providers]
    DHT --> RequestBlocks[Request Blocks from Peers]
    RequestBlocks --> Verify[Verify Block Hashes]
    Verify --> Assemble[Assemble Content]
    Assemble --> Display
    
    Bridge --> Warning[Show Centralization Warning]
    Warning --> HTTPRequest[Make HTTP Request]
    HTTPRequest --> Display
```

### Transaction Flow

```mermaid
sequenceDiagram
    participant User
    participant UI
    participant Wallet
    participant Blockchain
    participant Network
    
    User->>UI: Initiate transaction
    UI->>Wallet: Create transaction
    Wallet->>Wallet: Sign transaction
    Wallet->>Blockchain: Submit transaction
    Blockchain->>Network: Broadcast to peers
    Network-->>Blockchain: Transaction included
    Blockchain-->>UI: Transaction confirmed
    UI-->>User: Show confirmation
```

## Network Architecture

### Peer Discovery and Connection Management

```mermaid
graph TB
    subgraph "Discovery Methods"
        Bootstrap[Bootstrap Nodes]
        mDNS[Local mDNS]
        DHT[Kademlia DHT]
        PeerExchange[Peer Exchange]
    end
    
    subgraph "Connection Management"
        ConnManager[Connection Manager]
        PeerStore[Peer Store]
        AddrBook[Address Book]
    end
    
    subgraph "Protocol Handlers"
        IdentifyHandler[Identify Handler]
        PingHandler[Ping Handler]
        KadHandler[Kademlia Handler]
        BitswapHandler[Bitswap Handler]
    end
    
    Bootstrap --> ConnManager
    mDNS --> ConnManager
    DHT --> PeerStore
    PeerExchange --> AddrBook
    
    ConnManager --> IdentifyHandler
    ConnManager --> PingHandler
    PeerStore --> KadHandler
    AddrBook --> BitswapHandler
```

### Network Topology

```mermaid
graph LR
    subgraph "Local Node"
        LocalPeer[Local Peer]
        Protocols[Protocol Stack]
    end
    
    subgraph "Direct Peers"
        Peer1[Peer 1]
        Peer2[Peer 2]
        Peer3[Peer 3]
    end
    
    subgraph "DHT Network"
        DHTNode1[DHT Node 1]
        DHTNode2[DHT Node 2]
        DHTNode3[DHT Node 3]
    end
    
    subgraph "Content Providers"
        Provider1[Provider 1]
        Provider2[Provider 2]
        Provider3[Provider 3]
    end
    
    LocalPeer <--> Peer1
    LocalPeer <--> Peer2
    LocalPeer <--> Peer3
    
    Peer1 <--> DHTNode1
    Peer2 <--> DHTNode2
    Peer3 <--> DHTNode3
    
    DHTNode1 <--> Provider1
    DHTNode2 <--> Provider2
    DHTNode3 <--> Provider3
```

## Security Model

### Trust Boundaries

```mermaid
graph TB
    subgraph "Trusted Zone"
        LocalStorage[Local Storage]
        PrivateKeys[Private Keys]
        WalletCore[Wallet Core]
    end
    
    subgraph "Semi-Trusted Zone"
        VerifiedContent[Verified Content]
        SignedTransactions[Signed Transactions]
        PinnedContent[Pinned Content]
    end
    
    subgraph "Untrusted Zone"
        NetworkPeers[Network Peers]
        ExternalContent[External Content]
        BridgePlugins[Bridge Plugins]
    end
    
    subgraph "Verification Layer"
        HashVerification[Hash Verification]
        SignatureVerification[Signature Verification]
        ConsensusVerification[Consensus Verification]
    end
    
    LocalStorage -.->|Protected| PrivateKeys
    PrivateKeys -.->|Isolated| WalletCore
    
    NetworkPeers -->|Verify| HashVerification
    ExternalContent -->|Verify| SignatureVerification
    BridgePlugins -->|Verify| ConsensusVerification
    
    HashVerification --> VerifiedContent
    SignatureVerification --> SignedTransactions
    ConsensusVerification --> PinnedContent
```

### Cryptographic Architecture

```mermaid
classDiagram
    class CryptoProvider {
        <<interface>>
        +sign(data: bytes, key: PrivateKey) Signature
        +verify(data: bytes, sig: Signature, key: PublicKey) bool
        +hash(data: bytes) Hash
        +encrypt(data: bytes, key: PublicKey) bytes
        +decrypt(data: bytes, key: PrivateKey) bytes
    }
    
    class Sr25519Provider {
        +sign(data: bytes, key: Sr25519PrivateKey) Sr25519Signature
        +verify(data: bytes, sig: Sr25519Signature, key: Sr25519PublicKey) bool
        +generate_keypair() (Sr25519PrivateKey, Sr25519PublicKey)
    }
    
    class Ed25519Provider {
        +sign(data: bytes, key: Ed25519PrivateKey) Ed25519Signature
        +verify(data: bytes, sig: Ed25519Signature, key: Ed25519PublicKey) bool
        +generate_keypair() (Ed25519PrivateKey, Ed25519PublicKey)
    }
    
    class EcdsaProvider {
        +sign(data: bytes, key: EcdsaPrivateKey) EcdsaSignature
        +verify(data: bytes, sig: EcdsaSignature, key: EcdsaPublicKey) bool
        +generate_keypair() (EcdsaPrivateKey, EcdsaPublicKey)
    }
    
    CryptoProvider <|-- Sr25519Provider
    CryptoProvider <|-- Ed25519Provider
    CryptoProvider <|-- EcdsaProvider
```

## Storage Architecture

### Local Storage Hierarchy

```mermaid
graph TB
    subgraph "Application Data"
        Config[Configuration]
        Cache[Content Cache]
        Bookmarks[Bookmarks]
        History[Browse History]
    end
    
    subgraph "IPFS Storage"
        Blockstore[Block Store]
        Datastore[Data Store]
        Keystore[Key Store]
        PinSet[Pin Set]
    end
    
    subgraph "Blockchain Data"
        ChainState[Chain State]
        TxHistory[Transaction History]
        WalletData[Wallet Data]
        Metadata[Chain Metadata]
    end
    
    subgraph "Security Storage"
        EncryptedKeys[Encrypted Keys]
        Certificates[Certificates]
        TrustedPeers[Trusted Peers]
    end
    
    Config --> Blockstore
    Cache --> Datastore
    Bookmarks --> PinSet
    
    ChainState --> WalletData
    TxHistory --> Metadata
    
    EncryptedKeys --> Keystore
    Certificates --> TrustedPeers
```

### Data Persistence Strategy

```mermaid
sequenceDiagram
    participant App
    participant StorageManager
    participant LocalDB
    participant IPFS
    participant Backup
    
    App->>StorageManager: Store data
    StorageManager->>LocalDB: Write to local storage
    StorageManager->>IPFS: Pin important data
    StorageManager->>Backup: Create backup
    
    Note over StorageManager: Periodic cleanup
    StorageManager->>LocalDB: Remove old cache
    StorageManager->>IPFS: Unpin unused content
    
    App->>StorageManager: Retrieve data
    StorageManager->>LocalDB: Check local storage
    alt Data not found locally
        StorageManager->>IPFS: Fetch from IPFS
        StorageManager->>LocalDB: Cache locally
    end
    StorageManager-->>App: Return data
```

## Component Interactions

### Inter-Component Communication

```mermaid
graph LR
    subgraph "Frontend (Tauri)"
        WebView[WebView]
        TauriCore[Tauri Core]
        JSBridge[JS Bridge]
    end
    
    subgraph "Backend (Rust)"
        AppCore[Application Core]
        Services[Service Layer]
        Network[Network Layer]
    end
    
    subgraph "Communication Channels"
        IPC[IPC Messages]
        Events[Event System]
        Commands[Command Interface]
    end
    
    WebView <--> JSBridge
    JSBridge <--> TauriCore
    TauriCore <--> IPC
    
    IPC <--> AppCore
    AppCore <--> Services
    Services <--> Network
    
    Events --> WebView
    Commands --> Services
```

### Event Flow Architecture

```mermaid
stateDiagram-v2
    [*] --> Idle
    
    Idle --> Processing: User Action
    Processing --> NetworkRequest: Content Request
    Processing --> WalletOperation: Transaction Request
    Processing --> ConfigUpdate: Settings Change
    
    NetworkRequest --> PeerDiscovery: Find Providers
    NetworkRequest --> ContentFetch: Fetch Content
    NetworkRequest --> ContentVerify: Verify Content
    
    WalletOperation --> KeyManagement: Access Keys
    WalletOperation --> TransactionSign: Sign Transaction
    WalletOperation --> TransactionBroadcast: Broadcast Transaction
    
    ConfigUpdate --> StorageUpdate: Update Storage
    ConfigUpdate --> UIUpdate: Update Interface
    
    ContentVerify --> Success: Valid Content
    ContentVerify --> Error: Invalid Content
    
    TransactionBroadcast --> Success: Transaction Sent
    TransactionBroadcast --> Error: Transaction Failed
    
    Success --> Idle
    Error --> Idle
    StorageUpdate --> Idle
    UIUpdate --> Idle
```

## Design Decisions

### 1. Modular Architecture
- **Rationale**: Enables independent development and testing of components
- **Trade-offs**: Increased complexity vs. maintainability
- **Implementation**: Rust workspace with separate crates

### 2. libp2p for Networking
- **Rationale**: Mature, well-tested P2P networking stack
- **Benefits**: Multi-transport, security, protocol extensibility
- **Challenges**: Learning curve, dependency management

### 3. Tauri for UI
- **Rationale**: Native performance with web technologies
- **Benefits**: Cross-platform, security, small bundle size
- **Trade-offs**: Limited to desktop platforms initially

### 4. Embedded Light Clients
- **Rationale**: Eliminates dependency on external RPC providers
- **Benefits**: True decentralization, privacy, reliability
- **Challenges**: Resource usage, sync time, complexity

## Performance Considerations

### Resource Management

```mermaid
pie title Resource Allocation
    "Network I/O" : 35
    "Content Processing" : 25
    "UI Rendering" : 20
    "Blockchain Sync" : 15
    "Storage Operations" : 5
```

### Optimization Strategies

1. **Lazy Loading**: Load components only when needed
2. **Content Caching**: Aggressive caching of frequently accessed content
3. **Peer Selection**: Optimize peer selection for performance
4. **Background Processing**: Move heavy operations to background threads
5. **Memory Management**: Efficient memory usage with Rust's ownership model

## Future Architecture Considerations

### Scalability Improvements
- Mobile platform support
- WebAssembly plugins
- Advanced caching strategies
- Distributed computation

### Security Enhancements
- Hardware security module integration
- Zero-knowledge proof verification
- Advanced privacy features
- Formal verification of critical components

This architecture provides a solid foundation for a truly decentralized browser while maintaining performance, security, and user experience standards.
