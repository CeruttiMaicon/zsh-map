# Instalação de programas (fora deste repositório)

Os scripts `.sh` por sistema operacional (ex.: `ubuntu/`) **não** ficam no repositório **zsh-map**.

1. Guarda-os num ou mais repositórios ou pastas **à tua escolha**.
2. No **`~/.zshmap.yml`**, define **`install.programs_dir` como lista** (sempre em formato YAML array), por exemplo:

```yaml
install:
  programs_dir:
    - "~/Projects/substitui-pelo-repo/programs"
    - "~/Projects/outro-repo/outros-programs"
```

3. É preciso **yq** no PATH para o ZshMap ler o YAML.

Se a lista estiver vazia, for só texto (não array), ou nenhuma das pastas tiver `.sh`, a opção **Instalação de Programas** não aparece no menu.
