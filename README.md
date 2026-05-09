# Free Gamepass/Product Script Roblox
```luau
getgenv().Settings = {
    CopyButton = false,
    -------------------
    AutoButton = false,
    AutoInterval = 0.1,
    -------------------
    InstantPurchase = false
}

loadstring(game:HttpGet("https://raw.githubusercontent.com/7yd7/FreeGamepass/main/Script.luau"))()
```

## Warning: This script will not work in all games.
Some games already patched the [PromptProductPurchaseFinished](https://devforum.roblox.com/t/promptproductpurchasefinished-vulnerability-fix-free-gamepasses-dev-products/2943231) vulnerability, so the exploit can no longer be used there.
It only works in games that have not patched it yet

## How to know if it works?
Just test the script yourself. Sometimes it works on certain gamepasses/products, and sometimes it does not.
It depends on the game and whether the developer patched the vulnerability or not.
Basically, it’s your luck.

I highly recommend putting the script in AutoExec if you join random games.

## Settings
* CopyButton: Creates a copy button for the GamePass/Product so you can use it anywhere you want.
* AutoButton: Creates a Auto button Runs the GamePass/Product loop.
* InstantPurchase: InstantPurchase: Instantly completes purchases and closes the prompt gamepasses/products.

## Games to try out a working script
[Troll Easy Tower 👋](https://www.roblox.com/games/18458777099/Balloon-Game) | [WATER POLICE PRISON RUN! (Obby)](https://www.roblox.com/games/74377594190764/WATER-POLICE-PRISON-RUN) | [GUGUGAGA Penguin Prison Run!](https://www.roblox.com/games/125121521180859/GUGUGAGA-Penguin-Prison-Run) (Just a troll)
