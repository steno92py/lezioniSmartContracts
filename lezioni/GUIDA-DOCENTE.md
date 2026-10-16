# Guide del docente — tutte le 17 lezioni

[Indice del corso](../README.md#indice-delle-lezioni) · [Risorse comuni](../risorse/README.md)

Scegli nella tabella il copione da tenere aperto durante la lezione. Per iniziare il percorso, apri la [guida 1](01-transazioni-account-calldata-storage-revert/copione.md).

Tutti i **17 copioni sono stati riscritti** con discorso da dire ad alta voce, esempi svolti, lettura guidata del codice, domande con risposte e percorsi da 60/90 minuti. I tempi includono demo, lettura, esercizi e discussione: non sono minuti di solo monologo. La riscrittura riguarda le guide del docente; i documenti teorici collegati restano materiale di approfondimento.

Ogni guida raccoglie scaletta, testo da dire, raccordi fra argomenti, file da mostrare, comandi e risultati attesi. Sono previsti un percorso da 90 minuti e uno da 60, domande con risposta, precisazioni tecniche e un percorso alternativo se la demo si interrompe. Gli appunti teorici e gli esercizi restano raggiungibili dalla guida.

Le **lezioni 16 e 17 hanno inoltre un copione esteso da 180 minuti ciascuna**, divisibile in due incontri da 90. Accompagnano l'intera catena requisito → ipotesi → prova → finding → patch → retest → report, con letture per funzioni e scritture, conti svolti, previsioni prima delle demo e restituzioni degli studenti. I percorsi da 60/90 minuti selezionano i passaggi indicati nei copioni: non richiedono di leggere tutto più velocemente.

## Scegli la lezione

| Lezione | Guida da tenere aperta | Codice ed esercizi | Test nella suite ordinaria |
| --- | --- | --- | ---: |
| 01 | [Transazioni, account, calldata, storage e revert](01-transazioni-account-calldata-storage-revert/copione.md) | [Laboratorio](01-transazioni-account-calldata-storage-revert/README.md) | 19 |
| 02 | [Foundry e metodo di testing](02-foundry-e-metodo-di-testing/copione.md) | [Laboratorio](02-foundry-e-metodo-di-testing/README.md) | 14 |
| 03 | [Escrow e macchina a stati](03-escrow-e-macchina-a-stati/copione.md) | [Laboratorio](03-escrow-e-macchina-a-stati/README.md) | 24 |
| 04 | [Ether, receive, fallback, chiamate esterne e CEI](04-ether-receive-fallback-chiamate-esterne-cei/copione.md) | [Laboratorio](04-ether-receive-fallback-chiamate-esterne-cei/README.md) | 18 |
| 05 | [Reentrancy, CEI e guard](05-reentrancy/copione.md) | [Laboratorio](05-reentrancy/README.md) | 8 |
| 06 | [Access control](06-access-control/copione.md) | [Laboratorio](06-access-control/README.md) | 21 |
| 07 | [Errori logici e state machine](07-errori-logici-e-state-machine/copione.md) | [Laboratorio](07-errori-logici-e-state-machine/README.md) | 31 |
| 08 | [ERC-20, allowance e integrazioni sicure](08-erc20-allowance-e-integrazioni-sicure/copione.md) | [Laboratorio](08-erc20-allowance-e-integrazioni-sicure/README.md) | 29 |
| 09 | [Oracoli, prezzi, slippage e MEV](09-oracoli-prezzi-slippage-mev/copione.md) | [Laboratorio](09-oracoli-prezzi-slippage-mev/README.md) | 27 |
| 10 | [Composability e dipendenze esterne](10-composability-e-dipendenze-esterne/copione.md) | [Laboratorio](10-composability-e-dipendenze-esterne/README.md) | 33 |
| 11 | [Proxy, delegatecall e upgradeability](11-proxy-delegatecall-upgradeability/copione.md) | [Laboratorio](11-proxy-delegatecall-upgradeability/README.md) | 25 |
| 12 | [Governance, owner, multisig e timelock](12-governance-owner-multisig-timelock/copione.md) | [Laboratorio](12-governance-owner-multisig-timelock/README.md) | 31 |
| 13 | [Testing approfondito con Foundry](13-testing-approfondito-con-foundry/copione.md) | [Laboratorio](13-testing-approfondito-con-foundry/README.md) | 42 |
| 14 | [Fuzz testing e invariant testing con Foundry](14-fuzz-e-invariant-testing-con-foundry/copione.md) | [Laboratorio](14-fuzz-e-invariant-testing-con-foundry/README.md) | 31 |
| 15 | [Analisi statica con Slither](15-analisi-statica-con-slither/copione.md) | [Laboratorio](15-analisi-statica-con-slither/README.md) | 12 |
| 16 | [Metodologia di audit completa](16-metodologia-di-audit-completa/copione.md) | [Laboratorio](16-metodologia-di-audit-completa/README.md) | 14 |
| 17 | [Progetto finale: audit dell’Escrow evoluto](17-progetto-finale-audit-escrow-evoluto/copione.md) | [Laboratorio](17-progetto-finale-audit-escrow-evoluto/README.md) | 31 |

## Preparazione comune

1. Apri la guida e raggiungi la cartella della lezione con il comando indicato.
2. Prima dell’aula, esegui `forge build` per preparare compilatore e dipendenze, poi `bash demo.sh check` per verificare la suite completa.
3. Usa `bash demo.sh help` per vedere le demo disponibili. Durante la lezione esegui i comandi brevi della guida, restando nella stessa cartella.
4. Se il terminale non è disponibile, mostra il test collegato e leggi le asserzioni con il risultato atteso: ogni blocco contiene il punto didattico da conservare.

Le demo Foundry sono locali e usano la modalità offline; non richiedono wallet, chiavi, RPC o Anvil. Il primo allestimento richiede Foundry, forge-std e il compilatore indicato dal progetto. La [procedura iniziale del corso](../README.md#come-scaricare-il-corso) spiega come prepararli.

Un test verde può dimostrare un difetto intenzionale: guarda sempre che cosa afferma il test. Nella lezione 2 il profilo separato `mutation` deve invece fallire sul controllo della fee: è il risultato previsto dell’esercizio. Le campagne invariant possono stampare più proprietà ma essere contate come un unico test nel riepilogo Foundry; i numeri della tabella seguono quel riepilogo.

Per la **lezione 15**, il controllo Foundry verifica le prove eseguibili, non l’esecuzione di Slither. La guida separa la preparazione dello strumento dal percorso su inventario e triage già disponibili. Per le lezioni 16–17, anche il percorso esteso è un laboratorio guidato: la consegna autonoma richiede di produrre il proprio ragionamento. I copioni distinguono esecuzione delle prove, lettura del codice ed esempi su carta; Slither può essere discusso sul dossier se l'ambiente non è preparato.

## Differenze da esplicitare durante il corso

I laboratori sono progetti autonomi, non versioni successive di un unico contratto. Prima di riutilizzare una regola, controlla la specifica della lezione.

| Passaggio | Precisazione da dire |
| --- | --- |
| 8 → 13 | La 8 mostra l'accredito del netto ricevuto; la 13 rifiuta atomicamente i depositi che ricevono meno del richiesto. |
| 10 → 11 → 12 | Alcuni componenti isolano solo una proprietà: NotificationEscrow registra la release, UpgradeableEscrow registra amount, GovernedEscrow simula azione e uscita con contatori. Queste demo non dimostrano un pagamento reale. |
| 13 → 14 | I casi scelti manualmente restano utili per confini e regressioni; fuzz e invariant ampliano input e sequenze, mantenendo necessarie asserzioni significative. |
| 13–14 → 16 | Nella 16 l'età del prezzo deve essere strettamente minore del limite: il confine esatto è rifiutato. Nelle 13–14 è accettato. |
| 16 → 17 | La 16 rifiuta token con fee in ingresso e consente release a qualsiasi caller alle condizioni previste; la 17 accredita il ricevuto effettivo e riserva release al buyer. Il confine di freschezza nella 17 è incluso. |
| Fee della 13 → fee della 17 | Nella 13 la commissione viene trasferita all'owner. Nella 17 i residui e la loro destinazione richiedono la discussione indicata nel copione: non presumere lo stesso flusso. |

I risultati delle demo sono **attesi**, da leggere insieme alle asserzioni. La revisione editoriale dei copioni ha controllato collegamenti, percorsi dei file e nomi dei comandi; non equivale a una nuova esecuzione delle suite.
