# Online CoinCoin Server #

Online Coincoin Server permet de remplacer les backend.php et post.php en ajoutant une couche serveur qui va chercher les remote.xml des différentes tribunes, indexe les posts et remet à disposition des backend en json ou xml, en plus d'autres fonctionnalités

Les buts sont de palier les problèmes de lenteur de certaines tribunes, et d'avoir la possibilité de recherche avancéee sur les posts archivés.

On pourra par exemple construire des backends multitribunes, avoir des bigornophones cross tribunes, des bloub detector de pointe, tout en ayant un rendu rapide des remote sur les tribunes les plus lentes, et ainsi éviter le croixroutage dans olcc, et améliorer la charge sur les serveurs legacy par la baisse du nombre des requêtes.
 
Online Coincoin Server est composé de:
 
*  Un programme ruby qui inclut:
 * un serveur web qui sert les remote.xml
 * un client web qui fetch les remote.xml des tribunes
 * un scheduler qui appelle régulièrement le moteur d'indexation
 * une interface avec ElasticSearch pour indexer le contenu des backend des tribunes
* Un elasticsearch comme système de stockage des donnéees avec indexation
 
## Le programme ruby ##

Le programme Ruby est (pour l'instant) écrit avec les librairies principales suivantes:

* Thin pour la partie serveur Web (http://code.macournoyer.com/thin/)
* sinatra pour la partie framework web (http://www.sinatrarb.com)
* EventMachine et Synchrony pour la partie framework I/O asynchrone (http://rubyeventmachine.com/ et https://github.com/igrigorik/em-synchrony)
* Nokogiri pour le parsing et le rendu xml (http://nokogiri.org/)
* JSON pour le parsing json (http://flori.github.com/json/) 

Au démarrage, on initialise les tribunes présentes dans le fichier boards.yml, on compare les Id des derniers posts présents sur la tribune d'origine et dans le système de stockage pour prendre en compte le plus grand en tant que lastid pour cette tribune.

Toutes les 30 secondes, on va chercher les remotes des différentes tribunes (avec gestion du lastid), et on indexe les nouveaux posts dans ElasticSearch, dans la partie de l'index qui correspond la tribune: tribune/post/id, par exemple dlfp/post/42.

Le serveur Web est utilisé à l'appel du backend remote par un client (.json ou .xml). Afin d'éviter d'aller chercher à chaque fois le backend dans ElasticSearch, un cache existe, invalidé à chaque indexation d'au moins un post.

La gestion du post d'un nouveau message se fait comme pour le post.php d'origine: olcc envoie toutes les infos nécessaires (cookie, login, etc.), le composant qui gère ça ne sert que de passe plat. Il lance ensuite une réindexation du backend d'origine.

## ElasticSearch ##

http://www.elasticsearch.org/

Un espèce de moteur noSQL basé sur un stockage Lucene et interropérable grace à une interface REST. Il indexe les documents qu'on lui donne, et stocke la source initiale, ce qui nous permet de reconstruire les remote à partir des posts donnés en indexation. Un mapping est utilisé afin d'optimiser l'indexation. Ainsi, seul le message est analysé avant d'être indexé.

Chaque tribune dispose de son index, lui même décomposé en type de document (pour l'instant qu'un seul: post, mais on pourrait imaginer stocker/indexer des fortunes par exemple), qui contient les documents indexés. Individuellement, chaque élément est récupérable par un appel GET sur <tribune>/post/<id>.

Pour la reconstruction de documents plus complexes, comme un remote, on effectue une recherche (appel GET avec données de la requête en json dans un paramètre). La réponse est ensuite interprétée dans le programme ruby.
