{
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            leftcontrol = "capslock";
            rightcontrol = "F13"; #F13 is unused otherwise; this binding is for activating voice transcription
            capslock = "layer(custom2)";
            meta = "layer(custom2)";
            "a" = "overloadt(meta, a, 130)";
            "s" = "overloadt(alt, s, 130)";
            "d" = "overloadt(control, d, 130)";
            "f" = "overloadt(shift, f, 130)";

            "h" = "overloadt(shift, h, 130)";
            "j" = "overloadt(control, j, 130)";
            "k" = "overloadt(alt, k, 130)";
            "l" = "overloadt(meta, l, 130)";

            "1" = "!";
            "2" = "@";
            "3" = "#";
            "4" = "$";
            "5" = "%";
            "6" = "^";
            "7" = "&";
            "8" = "*";
            "9" = "(";
            "0" = ")";
          };
          "custom2:211" = {
            "kp1" = "1";
            "kp2" = "2";
            "kp3" = "3";
            "kp4" = "4";
            "kp5" = "5";
            "kp6" = "6";
            "kp7" = "7";
            "kp8" = "8";
            "kp9" = "9";
            "kp0" = "0";
          };
        };
      };
    };
  };
}
