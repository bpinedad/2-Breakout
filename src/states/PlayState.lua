--[[
    GD50
    Breakout Remake

    -- PlayState Class --

    Author: Colton Ogden
    cogden@cs50.harvard.edu

    Represents the state of the game in which we are actively playing;
    player should control the paddle, with the ball actively bouncing between
    the bricks, walls, and the paddle. If the ball goes below the paddle, then
    the player should lose one point of health and be taken either to the Game
    Over screen if at 0 health or the Serve screen otherwise.
]]

PlayState = Class{__includes = BaseState}

--[[
    We initialize what's in our PlayState via a state table that we pass between
    states as we go from playing to serving.
]]
function PlayState:enter(params)
    self.paddle = params.paddle
    self.bricks = params.bricks
    self.health = params.health
    self.score = params.score
    self.highScores = params.highScores
    self.balls = {} 
    self.level = params.level

    self.recoverPoints = params.recoverPoints
    self.upgradeStep = 2000
    self.upgradePoints = params.upgradePoints

    -- Keep track og keys that the user have
    self.keys = params.keys

    -- give ball random starting velocity
    self.balls[1] = params.ball
    self.balls[1].dx = math.random(-200, 200)
    self.balls[1].dy = math.random(-50, -60)
end

function PlayState:update(dt)
    if self.paused then
        if love.keyboard.wasPressed('space') then
            self.paused = false
            gSounds['pause']:play()
        else
            return
        end
    elseif love.keyboard.wasPressed('space') then
        self.paused = true
        gSounds['pause']:play()
        return
    end

    -- update positions based on velocity
    self.paddle:update(dt)

    -- update for all existing balls
    local lostBalls = {}
    local addBalls = 0
    for k, ball in pairs(self.balls) do
        ball:update(dt)

        if ball:collides(self.paddle) then
            -- raise ball above paddle in case it goes below it, then reverse dy
            ball.y = self.paddle.y - 8
            ball.dy = -ball.dy

            --
            -- tweak angle of bounce based on where it hits the paddle
            --

            -- if we hit the paddle on its left side while moving left...
            if ball.x < self.paddle.x + (self.paddle.width / 2) and self.paddle.dx < 0 then
                ball.dx = -50 + -(8 * (self.paddle.x + self.paddle.width / 2 - ball.x))
            
            -- else if we hit the paddle on its right side while moving right...
            elseif ball.x > self.paddle.x + (self.paddle.width / 2) and self.paddle.dx > 0 then
                ball.dx = 50 + (8 * math.abs(self.paddle.x + self.paddle.width / 2 - ball.x))
            end

            gSounds['paddle-hit']:play()
        end

        -- detect collision across all bricks with the ball
        for k, brick in pairs(self.bricks) do

            -- only check collision if we're in play
            if brick.inPlay and ball:collides(brick) then
                -- first thing is to check key condition, if locked and no key, completely ignore
                if not brick.needsKey or (brick.needsKey and self.keys > 0) then

                    if (brick.needsKey) then
                        brick.needsKey = false
                        self.keys = self.keys - 1

                        -- Play unlock sound
                        gSounds['unlocked']:play()

                        self.score = self.score + 500 -- Assign 500 to key bricks
                    else
                        -- add to score
                        self.score = self.score + (brick.tier * 200 + brick.color * 25)

                        -- trigger the brick's hit function, which removes it from play
                        brick:hit()
                    end

                    -- if we have enough points, recover a point of health
                    if self.score > self.recoverPoints then
                        -- can't go above 3 health
                        self.health = math.min(3, self.health + 1)

                        -- multiply recover points by 2
                        self.recoverPoints = self.recoverPoints + math.min(100000, self.recoverPoints * 2)

                        -- play recover sound effect
                        gSounds['recover']:play()
                    end

                    -- if enough points to upgrade paddle
                    if self.score > self.upgradePoints then
                        -- multiply recover points by 2
                        self.upgradePoints = self.upgradePoints + self.upgradeStep

                        -- Increase paddle
                        self.paddle.size = math.min(self.paddle.size + 1, 4)
                        self.paddle.width = self.paddle.size * 32

                        -- play increase sound effect
                        gSounds['paddleIncrease']:play()
                    end

                    -- go to our victory screen if there are no more bricks left
                    if self:checkVictory() then
                        gSounds['victory']:play()

                        gStateMachine:change('victory', {
                            level = self.level,
                            paddle = self.paddle,
                            health = self.health,
                            score = self.score,
                            highScores = self.highScores,
                            ball = ball,
                            recoverPoints = self.recoverPoints,
                            upgradePoints = self.upgradePoints,
                            keys = 0
                        })
                    end
                else
                    -- Metal sound against locked brick
                    gSounds['lockedHit']:play()
                end

                --
                -- collision code for bricks
                --
                -- we check to see if the opposite side of our velocity is outside of the brick;
                -- if it is, we trigger a collision on that side. else we're within the X + width of
                -- the brick and should check to see if the top or bottom edge is outside of the brick,
                -- colliding on the top or bottom accordingly 
                --

                -- left edge; only check if we're moving right, and offset the check by a couple of pixels
                -- so that flush corner hits register as Y flips, not X flips
                if ball.x + 2 < brick.x and ball.dx > 0 then
                    
                    -- flip x velocity and reset position outside of brick
                    ball.dx = -ball.dx
                    ball.x = brick.x - 8
                
                -- right edge; only check if we're moving left, , and offset the check by a couple of pixels
                -- so that flush corner hits register as Y flips, not X flips
                elseif ball.x + 6 > brick.x + brick.width and ball.dx < 0 then
                    
                    -- flip x velocity and reset position outside of brick
                    ball.dx = -ball.dx
                    ball.x = brick.x + 32
                
                -- top edge if no X collisions, always check
                elseif ball.y < brick.y then
                    
                    -- flip y velocity and reset position outside of brick
                    ball.dy = -ball.dy
                    ball.y = brick.y - 8
                
                -- bottom edge if no X collisions or top collision, last possibility
                else
                    
                    -- flip y velocity and reset position outside of brick
                    ball.dy = -ball.dy
                    ball.y = brick.y + 16
                end

                -- slightly scale the y velocity to speed up the game, capping at +- 150
                if math.abs(ball.dy) < 150 then
                    ball.dy = ball.dy * 1.02
                end

                -- only allow colliding with one brick, for corners
                break
            -- if not in play anymore look for collision with corresponding powerup
            elseif brick.powerUp.enabled and brick.powerUp:collides(self.paddle) then
                -- Handle depending on power up
                -- Multiball case
                if (brick.powerUp.skin == 1) then
                    addBalls = addBalls + 2
                elseif (brick.powerUp.skin == 2) then
                    self.keys = self.keys + 1
                end
            end
        end

        -- if ball goes below bounds, revert to serve state and decrease health
        if ball.y >= VIRTUAL_HEIGHT then
            -- Remove ball from table
            -- add to list to remove later. Save index not ball
            lostBalls[#lostBalls + 1] = k
        end
    end

    -- If needed, add new balls after for loop to avoid skipping indexes
    for i = 1, addBalls do
        --Create to balls from paddle
        local tmpx = self.paddle.x + (self.paddle.width / 2) - 4
        local tmpy = self.paddle.y - 8
        
        -- Init new ball
        self.balls[#self.balls + 1] = Ball()
        self.balls[#self.balls].x = tmpx
        self.balls[#self.balls].y = tmpy
        self.balls[#self.balls].dx = math.random(-200, 200)
        self.balls[#self.balls].dy = math.random(-50, -60)
        self.balls[#self.balls].skin = math.random(7)
    end

    -- Remove lost balls
    for k, ball in pairs(lostBalls) do
        table.remove(self.balls, ball)
    end

    -- Verify if any balls exist still
    -- If no more balls, remove health
    if #self.balls == 0 then
        self.health = self.health - 1
        gSounds['hurt']:play()

        if self.health == 0 then
            gStateMachine:change('game-over', {
                score = self.score,
                highScores = self.highScores
            })
        else
            -- If lost health, reduce paddle size
            self.paddle.size = math.max(self.paddle.size - 1, 1)
            self.paddle.width = self.paddle.size * 32

            gStateMachine:change('serve', {
                paddle = self.paddle,
                bricks = self.bricks,
                health = self.health,
                score = self.score,
                highScores = self.highScores,
                level = self.level,
                recoverPoints = self.recoverPoints,
                upgradePoints = self.upgradePoints,
                keys = self.keys
            })
        end
    end    

    -- for rendering particle systems
    for k, brick in pairs(self.bricks) do
        brick:update(dt)
    end

    if love.keyboard.wasPressed('escape') then
        love.event.quit()
    end
end

function PlayState:render()
    -- render bricks
    for k, brick in pairs(self.bricks) do
        brick:render()
    end

    -- render all particle systems
    for k, brick in pairs(self.bricks) do
        brick:renderParticles()
    end

    self.paddle:render()
    for k, ball in pairs(self.balls) do
        ball:render()
    end

    renderScore(self.score)
    renderHealth(self.health)

    -- pause text, if paused
    if self.paused then
        love.graphics.setFont(gFonts['large'])
        love.graphics.printf("PAUSED", 0, VIRTUAL_HEIGHT / 2 - 16, VIRTUAL_WIDTH, 'center')
    end
end

function PlayState:checkVictory()
    for k, brick in pairs(self.bricks) do
        if brick.inPlay then
            return false
        end 
    end

    return true
end