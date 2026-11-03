{
  fetchFromCodeberg,
  buildGoModule,
  lib,
  coreutils,
}:
buildGoModule rec {
  pname = "graft-kernel";
  version = "0.1.0";

  src = fetchFromCodeberg {
    owner = "Gardenhouse";
    repo = pname;
    rev = "bd7fe00503094510f4a37f4da86b5d0337269f38";
    hash = "sha256-UUBJ4DYXyuvnjBXUFy9ZYWgDN3n0kCypfu++l60zRkA=";
  };
  vendorHash = null;

  meta = {
    description = "A uki builder similiar to ukify that supports pcr measurments, secureboot and multi-stage UKIs";
    mainProgram = "graft-kernel";
    homepage = "https://codeberg.org/${src.owner}/${pname}";
    license = lib.licenses.gpl3Only;
    maintainers = [
      "z4il"
    ];
  };
}
