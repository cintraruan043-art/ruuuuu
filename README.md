# Figurinha

App iOS (SwiftUI) para criar figurinhas de WhatsApp a partir de fotos e vídeos.

- Foto ou vídeo (até 5 s), cortar trecho, zoom/arrastar, girar, espelhar, forma, borda, filtros, texto
- Figurinha animada (WebP, máx. 500 KB) e estática (WebP, máx. 100 KB)
- Som: gravar voz, importar arquivo ou usar o som do vídeo; gera MP4 com som
- Tema claro/escuro e cores personalizadas (aba Ajustes)
- Pacote salvo no aparelho

Todos os arquivos estão na raiz do repositório. Workflow do Codemagic: `ipa-sem-assinatura`.

Observação: a API de importação de pacotes do WhatsApp ainda não aceita áudio para apps de terceiros.
Para criar figurinha com som, salve o vídeo com som e use o criador do próprio WhatsApp.
