# Description
Run gpt4free in Termux.

https://f-droid.org/en/packages/com.termux

https://github.com/xtekky/gpt4free

# Instructions
In Termux -

```
curl -L https://raw.githubusercontent.com/George-Seven/gpt4free-Termux/main/g4f.sh -o $PREFIX/bin/g4f.sh; chmod 755 $PREFIX/bin/g4f.sh
```
```
g4f.sh --help
```
```
g4f.sh --install
```
```
g4f.sh --script /path/to/script.py
```
```
g4f.sh --gui
```
```
g4f.sh "what chatgpt-4 needs to do -> the block of text to process"
```

```
Usage: g4f.sh "QUERY" | -i | -u | -s | -g | -h | --help

More options and descriptions -
  -i, --install  Install dependencies and
                 setup g4f container.

  -u, --update   Updates g4f inside container.
                 Equivalent to running :-
                  "pip3 install -U g4f"

  -s, --script   Pass a Python script to run
                 inside the container.

  -g, --gui      Run the g4f GUI

  -c, --cmd      Pass arguments to the container

  -p, --pip      Install python modules inside container
                 Use it as :-
                  --pip module1 module2 module3...

  -l, --login    Login to the container

Example for "QUERY" -

  g4f.sh "what chatgpt-4 needs to do -> the block of text to process"


Try example -

  g4f.sh "extract my otp, do not make it bold, do not write extra sentences only the number -> hello your otp, not the account which is 1234, is 9270. thanks"

You will get the output 9270 and avoid the account number
```

etc.

### Why
The `g4f` package is broken in Termux.

You *can* install it by using `pip install g4f`, but essential packages are broken or bugged.

(eg- chromium/chromedriver random errors, unsupported duckduckgo web results option, unsupported curl-cffi[[1](https://github.com/yifeikong/curl_cffi/issues/74)][[2](https://github.com/yifeikong/curl-impersonate/issues/51#issuecomment-1977317131)], bugged undetected-chromedriver, ... )

In contrast, gpt4free provides an official **[Docker container](https://github.com/xtekky/gpt4free?tab=readme-ov-file#docker-container)** which solves all broken depencency issues.

But Docker requires root, which is why we use **[udocker](https://github.com/indigo-dc/udocker)**, a docker-like container manager that runs in userspace (that means no root).

Which means it can run in Termux, **without root**, for everyone.

Read the [instructions](https://github.com/George-Seven/gpt4free-Termux?tab=readme-ov-file#instructions), setup and use.
