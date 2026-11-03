# Local semantic search assets

Model: sentence-transformers/all-MiniLM-L6-v2 by the Sentence Transformers contributors.
Pinned revision: 1110a243fdf4706b3f48f1d95db1a4f5529b4d41
Publisher: https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
License: Apache-2.0 (see LICENSE).

Bundled vocab.txt: 231,508 bytes; SHA-256 07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3.
The optional ONNX ARM64 int8 model is downloaded only after opt-in: 23,026,053 bytes;
SHA-256 4278337fd0ff3c68bfb6291042cad8ab363e1d9fbc43dcb499fe91c871902474.

Inference uses uncased WordPiece, max 256 tokens, masked mean pooling (unpadded single input), and L2 normalization. Model output has 384 dimensions. Numeric amounts/dates are not embedded; source text is merchant, category and notes. An exact in-database vector index is used, not an approximate external database. Vectors are rebuildable and excluded from backups.
