# Naming

Why the module is called `greenbone` and its types `gvm_*` although the product is marketed as
OpenVAS.

As of July 2025, Greenbone rebranded its product line, and the free edition is now marketed as
OpenVAS Community Edition (formerly Greenbone Community Edition). The rebrand is cosmetic: the
underlying packages (`gvmd`, `ospd-openvas`, `greenbone-feed-sync`), the config paths (`/etc/gvm`,
`/etc/openvas`) and the GMP management protocol still carry the `greenbone` and `gvm` names. This
module deliberately keeps the `greenbone` namespace and the `gvm_*` resource types to stay aligned
with the software it manages.

Where this module says:

- Greenbone or Greenbone Community Edition: the product, whichever name it carries today.
- gvmd: the Greenbone Vulnerability Manager daemon that owns the data and speaks GMP.
- GMP: the Greenbone Management Protocol, the XML protocol the providers speak over gvmd's Unix
  socket ([GMP 22.5 reference](https://docs.greenbone.net/API/GMP/gmp-22.5.html)).
- OpenVAS: the scanner component (`openvas-scanner`, `ospd-openvas`), and the `OpenVAS Default`
  scanner that tasks reference by name.
- GVM account or GVM user: a login inside Greenbone (`gvm_user`), as opposed to the Unix system
  account the services run as (`gvm_user` class parameter of `greenbone`).
